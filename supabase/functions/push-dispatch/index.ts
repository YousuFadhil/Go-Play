// Push delivery. One function, one job: take a notification id and, if the
// database says so, hand the notice to Firebase.
//
// **There is no business logic here, and that is deliberate.** This function
// does not know what "high priority" means, does not read a preference, does
// not decide who the recipient is and does not compose the text. It calls
// `push_dispatch_payload`, which answers all four questions in SQL, and then
// either sends what it was given or does not. Changing the notification policy
// is a migration; changing how a push is transported is a deploy. Keeping those
// two separate is the whole point of the split.
//
// No queue, no retry, no delivery log. A push that fails is a push that did not
// arrive — the notice is already committed to the Notification Center, which is
// the source of truth, so nothing is lost that anyone can act on.
//
// Invoked by an `after insert` trigger on `public.notifications` via pg_net.
//
// Environment:
//   SUPABASE_URL              — injected by the platform
//   SUPABASE_SERVICE_ROLE_KEY — injected by the platform
//   PUSH_DISPATCH_SECRET      — must equal push_config.dispatch_secret
//   FCM_SERVICE_ACCOUNT       — the Firebase service account JSON, verbatim
//   PUSH_WEB_APP_URL          — optional; where a clicked web notification goes

interface DispatchPayload {
  notification_id: string;
  user_id: string;
  type: string;
  match_id: string | null;
  priority: string;
  category: string | null;
  // Both come from `notification_types`, which the payload only fills in for a
  // registered type — and an unregistered type is never `should_push`. Typed as
  // present because by the time anything is sent they are, and the handler
  // checks rather than inventing a fallback if that ever stops being true.
  title: string;
  body: string;
  should_push: boolean;
  tokens: string[];
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DISPATCH_SECRET = Deno.env.get("PUSH_DISPATCH_SECRET") ?? "";
// Optional, and web-only: the origin a clicked browser notification opens.
// Unset is a supported state — see the `webpush` block in `send`.
const WEB_APP_URL = Deno.env.get("PUSH_WEB_APP_URL") ?? "";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";

// ---------------------------------------------------------------------------
// Google access token
//
// Held between invocations while the runtime keeps this isolate warm. It is a
// cache, not a store: a cold start simply mints another one.
// ---------------------------------------------------------------------------

let cachedToken: { value: string; expiresAt: number } | null = null;

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FCM_SERVICE_ACCOUNT is not set");
  return JSON.parse(raw) as ServiceAccount;
}

function base64url(bytes: Uint8Array | string): string {
  const input = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of input) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// Turns the PEM private key from the service account into a signing key.
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/// The OAuth2 JWT-bearer grant, which is the only way into FCM HTTP v1.
async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64url(JSON.stringify({
    iss: account.client_email,
    scope: FCM_SCOPE,
    aud: TOKEN_ENDPOINT,
    iat: now,
    exp: now + 3600,
  }));

  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claim}`),
  );
  const jwt = `${header}.${claim}.${base64url(new Uint8Array(signature))}`;

  const response = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`Google token request failed: ${await response.text()}`);
  }

  const json = await response.json() as { access_token: string; expires_in: number };
  cachedToken = { value: json.access_token, expiresAt: now + json.expires_in };
  return json.access_token;
}

// ---------------------------------------------------------------------------
// The database
// ---------------------------------------------------------------------------

async function loadPayload(notificationId: string): Promise<DispatchPayload | null> {
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/rpc/push_dispatch_payload`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ p_notification_id: notificationId }),
    },
  );

  if (!response.ok) {
    throw new Error(`push_dispatch_payload failed: ${await response.text()}`);
  }
  return await response.json() as DispatchPayload | null;
}

/// Forgets a device Firebase has told us no longer exists.
///
/// Not delivery tracking — there is none. A token that FCM reports as
/// unregistered is an uninstalled app or a reset device, and keeping it would
/// mean sending to it forever.
async function forgetToken(token: string): Promise<void> {
  await fetch(
    `${SUPABASE_URL}/rest/v1/notification_push_tokens?token=eq.${encodeURIComponent(token)}`,
    {
      method: "DELETE",
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
    },
  );
}

// ---------------------------------------------------------------------------
// Firebase
// ---------------------------------------------------------------------------

async function send(
  account: ServiceAccount,
  bearer: string,
  deviceToken: string,
  payload: DispatchPayload,
): Promise<"sent" | "stale" | "failed"> {
  const highPriority = payload.priority === "high";

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${bearer}`,
      },
      body: JSON.stringify({
        message: {
          token: deviceToken,
          // Both authored in `notification_types`. Nothing here composes,
          // truncates or falls back — a presentation decision taken in this
          // file would be one the database could not see.
          notification: { title: payload.title, body: payload.body },
          // What the app needs to open the right screen when the push is
          // tapped. The Notification Center is still where it reads the notice
          // itself — this is a pointer, not a copy.
          data: {
            notification_id: payload.notification_id,
            type: payload.type,
            match_id: payload.match_id ?? "",
          },
          // Delivery urgency follows the registry's priority rather than being
          // fixed at high for everything. A medium notice that wakes a sleeping
          // phone is the same interruption as a high one, which would make the
          // distinction the database draws invisible where it is felt most.
          android: { priority: highPriority ? "high" : "normal" },
          apns: {
            headers: { "apns-priority": highPriority ? "10" : "5" },
            payload: { aps: { sound: "default" } },
          },
          // The web needs its own block, and unlike the two above it is not
          // only about urgency.
          //
          // A browser does not draw a `notification` block by itself: FCM
          // delivers the message to a service worker over Web Push and the
          // worker decides what to show. `web/firebase-messaging-sw.js` reads
          // `notification` out of the delivered payload, so the title and body
          // are repeated here — the generic block does not survive into the
          // webpush payload on its own, and a worker with nothing to render
          // would drop the push silently.
          //
          // `tag` is the notice id, which is what stops a browser coalescing
          // two different time changes into one notification.
          webpush: {
            headers: {
              Urgency: highPriority ? "high" : "normal",
              // A day. A push older than that is reporting a change the player
              // has already seen in the app, and delivering it then is worse
              // than not delivering it.
              TTL: "86400",
            },
            notification: {
              title: payload.title,
              body: payload.body,
              icon: "/icons/Icon-192.png",
              badge: "/icons/Icon-192.png",
              tag: payload.notification_id,
            },
            // Where a click lands, and the only thing that decides it: the
            // Firebase SDK in the service worker handles `notificationclick`
            // itself and opens this link. **Without it a click closes the
            // notification and does nothing else**, because the SDK's handler
            // returns early with no link and calls `stopImmediatePropagation`,
            // so a fallback listener in the worker could not run either.
            //
            // Omitted entirely rather than guessed when unset — `JSON.stringify`
            // drops an undefined value — since this function knows the Firebase
            // project but not the site the app is served from. A wrong link
            // opens a wrong site; a missing one costs the click and nothing
            // more, and the notice is in the Notification Center either way.
            fcm_options: WEB_APP_URL ? { link: WEB_APP_URL } : undefined,
          },
        },
      }),
    },
  );

  if (response.ok) return "sent";

  const text = await response.text();
  // 404 UNREGISTERED and 400 on a malformed token both mean the same thing:
  // this device will never receive anything again.
  if (
    response.status === 404 ||
    text.includes("UNREGISTERED") ||
    text.includes("INVALID_ARGUMENT")
  ) {
    await forgetToken(deviceToken);
    return "stale";
  }

  console.error(`FCM send failed (${response.status}): ${text}`);
  return "failed";
}

// ---------------------------------------------------------------------------

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // The trigger proves it is the trigger. Without this the function is an open
  // endpoint that will push anything to anybody who can guess a notice id.
  if (
    DISPATCH_SECRET === "" ||
    request.headers.get("x-push-secret") !== DISPATCH_SECRET
  ) {
    return new Response("Forbidden", { status: 403 });
  }

  let notificationId: string;
  try {
    const body = await request.json() as { notification_id?: string };
    if (!body.notification_id) throw new Error("notification_id is required");
    notificationId = body.notification_id;
  } catch (error) {
    return new Response(String(error), { status: 400 });
  }

  try {
    const payload = await loadPayload(notificationId);

    // Not an error in either case. A notice can be deleted between the trigger
    // firing and this running, and a notice the policy says not to push is the
    // ordinary outcome for every low-priority type.
    if (!payload) return Response.json({ status: "not_found" });
    if (!payload.should_push) {
      return Response.json({ status: "suppressed", priority: payload.priority });
    }
    if (payload.tokens.length === 0) {
      return Response.json({ status: "no_devices" });
    }
    // Unreachable while `push_title` is NOT NULL and only registered types are
    // pushed. Checked rather than assumed, because the alternative to a title
    // is a title this file made up — and that is precisely the coupling the
    // registry exists to prevent.
    if (!payload.title || !payload.body) {
      return Response.json({ status: "unrenderable", type: payload.type });
    }

    const account = serviceAccount();
    const bearer = await accessToken(account);
    const results = await Promise.all(
      payload.tokens.map((token) => send(account, bearer, token, payload)),
    );

    return Response.json({
      status: "dispatched",
      sent: results.filter((r) => r === "sent").length,
      stale: results.filter((r) => r === "stale").length,
      failed: results.filter((r) => r === "failed").length,
    });
  } catch (error) {
    console.error(error);
    return new Response(String(error), { status: 500 });
  }
});
