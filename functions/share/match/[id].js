// Cloudflare Pages Function: GET /share/match/:id
//
// The one link a match invitation shares. A chat app fetches it, reads the
// Open Graph tags from the server-rendered HTML and builds a preview card out
// of them; a person who opens it is moved straight on to the app's own match
// route (`/#/match/:id`). Nothing here renders the app.
//
// DATA. The only read is the existing `public_match_detail(p_match_id)` RPC
// (migration 0079): `SECURITY DEFINER`, executable by `anon`, and empty for a
// match that is not publicly visible. It is called with the project's
// publishable (anon) key and with nothing else -- there is no service-role key
// anywhere in this file and none may be added. Of the row it returns, only the
// match title, location, start/end, and community name are ever used; the
// lineup, scores, MVP and community logo are never read into the page.
//
// RUNTIME BINDINGS (set in the Pages project, not in this repository):
//   SUPABASE_URL        https://<project>.supabase.co
//   SUPABASE_ANON_KEY   the publishable/anon key (the same one the web build
//                       already embeds in its bundle)
// Without them the function still answers, with the generic Go Play preview.
//
// Everything dynamic is HTML-escaped; the id is validated as a UUID before it
// is used anywhere; an unavailable match, a missing binding and an upstream
// failure all end in the same safe generic preview rather than an error page.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const LANGUAGES = ['ar', 'en'];
const DEFAULT_LANGUAGE = 'ar'; // what the app itself falls back to
const SUPABASE_TIMEOUT_MS = 3500;

// One reusable thumbnail, shipped with the web build (app/web/og/).
const IMAGE_PATH = '/og/go-play-match-invite.jpg';
const IMAGE_TYPE = 'image/jpeg';
const IMAGE_WIDTH = 1200;
const IMAGE_HEIGHT = 630;

// Match times are shown as Oman reads them, the same fixed wall clock the app
// uses for anything that is not the reader's own device (time_format.dart).
const TIME_ZONE = 'Asia/Muscat';

const TITLE_MAX = 80;
const DESCRIPTION_MAX = 200;

const COPY = {
  ar: {
    dir: 'rtl',
    ogLocale: 'ar_AR',
    siteName: 'Go Play',
    fallbackTitle: 'دعوة إلى مباراة على Go Play',
    fallbackDescription: 'انضم إلى المباراة على Go Play: مباريات كرة القدم والفرق والتشكيلات لمجتمعك.',
    imageAlt: 'Go Play',
    open: 'فتح المباراة في Go Play',
    notAvailable: 'هذه الدعوة غير متاحة.',
    home: 'فتح Go Play',
  },
  en: {
    dir: 'ltr',
    ogLocale: 'en_US',
    siteName: 'Go Play',
    fallbackTitle: 'Match invitation on Go Play',
    fallbackDescription: 'Join the match on Go Play: community football, matches, teams and lineups.',
    imageAlt: 'Go Play',
    open: 'Open the match in Go Play',
    notAvailable: 'This invitation is not available.',
    home: 'Open Go Play',
  },
};

// ----------------------------------------------------------------------------
// text helpers

/** Escapes text for HTML text and double-quoted attribute values alike. */
export function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Characters that must never reach a preview: C0/C1 controls, the line and
// paragraph separators, and the bidi override/isolate family, which can
// reorder the text around them. Built from numeric ranges so the source holds
// no invisible characters.
const STRIPPED_RANGES = [
  [0x00, 0x1f],
  [0x7f, 0x9f],
  [0x2028, 0x2029],
  [0x202a, 0x202e],
  [0x2066, 0x2069],
];
const STRIPPED = new RegExp(
  `[${STRIPPED_RANGES.map(([a, b]) => `${String.fromCodePoint(a)}-${String.fromCodePoint(b)}`).join('')}]`,
  'g',
);

/** One line, no control or bidi-override characters, bounded by code points. */
export function clean(value, max) {
  const text = String(value ?? '')
    .replace(STRIPPED, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const points = Array.from(text);
  return points.length <= max ? text : `${points.slice(0, max - 1).join('').trimEnd()}…`;
}

export function isUuid(value) {
  return typeof value === 'string' && UUID.test(value);
}

export function chooseLanguage(url, request) {
  const asked = (url.searchParams.get('lang') || '').toLowerCase();
  if (LANGUAGES.includes(asked)) return { lang: asked, explicit: true };
  const header = (request.headers.get('accept-language') || '').toLowerCase();
  const first = header.split(',')[0]?.trim().split(/[-;]/)[0];
  if (LANGUAGES.includes(first)) return { lang: first, explicit: false };
  return { lang: DEFAULT_LANGUAGE, explicit: false };
}

function formatWhen(startIso, endIso, lang) {
  const start = new Date(startIso);
  if (Number.isNaN(start.getTime())) return '';
  // Latin digits in Arabic too, as the app shows them.
  const tag = lang === 'ar' ? 'ar-u-nu-latn' : 'en-US';
  try {
    const day = new Intl.DateTimeFormat(tag, {
      timeZone: TIME_ZONE,
      weekday: 'short',
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    }).format(start);
    const time = new Intl.DateTimeFormat(tag, {
      timeZone: TIME_ZONE,
      hour: 'numeric',
      minute: '2-digit',
    });
    const end = new Date(endIso);
    const range = Number.isNaN(end.getTime())
      ? time.format(start)
      : `${time.format(start)} – ${time.format(end)}`;
    return `${day} • ${range}`;
  } catch {
    return '';
  }
}

// ----------------------------------------------------------------------------
// metadata

export function invitationMetadata(row, lang) {
  const copy = COPY[lang];
  const name = clean(row?.title, TITLE_MAX) || clean(row?.location, TITLE_MAX);
  if (!name) return null;
  const parts = [
    formatWhen(row.start_at, row.end_at, lang),
    clean(row.location, 80),
    clean(row.community_name, 60),
  ].filter(Boolean);
  // Keeps the venue when it is the title (a match with no title of its own).
  const unique = parts.filter((part, index) => parts.indexOf(part) === index && part !== name);
  return {
    title: name,
    description: clean(unique.join(' • '), DESCRIPTION_MAX) || copy.fallbackDescription,
  };
}

export function fallbackMetadata(lang) {
  const copy = COPY[lang];
  return { title: copy.fallbackTitle, description: copy.fallbackDescription };
}

// ----------------------------------------------------------------------------
// rendering

/**
 * @param meta     {title, description}
 * @param opts     {lang, shareUrl, imageUrl, redirectPath|null, unavailable}
 */
export function renderHtml(meta, opts) {
  const copy = COPY[opts.lang];
  const t = escapeHtml(meta.title);
  const d = escapeHtml(meta.description);
  const share = escapeHtml(opts.shareUrl);
  const image = escapeHtml(opts.imageUrl);
  const target = opts.redirectPath ?? '/';
  const linkText = opts.redirectPath ? copy.open : copy.home;
  // The path is built from a validated UUID or is the constant '/', so
  // JSON.stringify yields a safe JavaScript string literal; the `<` guard keeps
  // it from ever closing the script element.
  const scriptTarget = JSON.stringify(target).replace(/</g, '\\u003c');

  return `<!doctype html>
<html lang="${opts.lang}" dir="${copy.dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${t}</title>
<meta name="description" content="${d}">
<meta name="robots" content="noindex, nofollow">
<link rel="canonical" href="${share}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="${escapeHtml(copy.siteName)}">
<meta property="og:locale" content="${copy.ogLocale}">
<meta property="og:title" content="${t}">
<meta property="og:description" content="${d}">
<meta property="og:url" content="${share}">
<meta property="og:image" content="${image}">
<meta property="og:image:secure_url" content="${image}">
<meta property="og:image:type" content="${IMAGE_TYPE}">
<meta property="og:image:width" content="${IMAGE_WIDTH}">
<meta property="og:image:height" content="${IMAGE_HEIGHT}">
<meta property="og:image:alt" content="${escapeHtml(copy.imageAlt)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${t}">
<meta name="twitter:description" content="${d}">
<meta name="twitter:image" content="${image}">
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#07341c;color:#fff;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:34rem;padding:2rem;text-align:center}
h1{font-size:1.5rem;margin:0 0 .75rem}
p{margin:.5rem 0;opacity:.85}
a{color:#3ddc84;font-weight:600}
</style>
</head>
<body>
<main>
<h1>${t}</h1>
<p>${d}</p>
${opts.unavailable ? `<p>${escapeHtml(copy.notAvailable)}</p>\n` : ''}<p><a id="open" href="${escapeHtml(target)}">${escapeHtml(linkText)}</a></p>
</main>
<script>location.replace(${scriptTarget});</script>
</body>
</html>
`;
}

// ----------------------------------------------------------------------------
// data

/** The public RPC, called with the publishable key only. Never throws. */
export async function fetchPublicMatch(env, id, fetchImpl = fetch) {
  const base = String(env?.SUPABASE_URL ?? '').trim().replace(/\/+$/, '');
  const key = String(env?.SUPABASE_ANON_KEY ?? '').trim();
  // https only, except a loopback address so the function can be run locally
  // against a stand-in Supabase; no real project is ever served that way.
  const loopback = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/.test(base);
  if (!(base.startsWith('https://') || loopback) || key === '') return { status: 'unconfigured' };

  const headers = {
    apikey: key,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  // A legacy anon key is a JWT and is also sent as the bearer token; a new
  // `sb_publishable_...` key is not a JWT and must travel in `apikey` alone.
  if (key.startsWith('eyJ')) headers.Authorization = `Bearer ${key}`;

  // An explicit controller and a timer that is always cleared: nothing is left
  // pending after the call, whichever way it ends.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SUPABASE_TIMEOUT_MS);
  try {
    const response = await fetchImpl(`${base}/rest/v1/rpc/public_match_detail`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ p_match_id: id }),
      signal: controller.signal,
    });
    if (!response.ok) return { status: 'error' };
    const rows = await response.json();
    // Anything but a list is not an answer to this question.
    if (!Array.isArray(rows)) return { status: 'error' };
    if (rows.length === 0) return { status: 'unavailable' };
    return { status: 'ok', row: rows[0] };
  } catch {
    return { status: 'error' };
  } finally {
    clearTimeout(timer);
  }
}

// ----------------------------------------------------------------------------
// handler

function respond(request, status, html, cacheControl) {
  const headers = {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': cacheControl,
    // Without ?lang= the page follows Accept-Language, so a cache must key on it.
    Vary: 'Accept-Language',
    'X-Content-Type-Options': 'nosniff',
  };
  return new Response(request.method === 'HEAD' ? null : html, { status, headers });
}

export async function handle(request, env, rawId, fetchImpl = fetch) {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method Not Allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
  }

  const url = new URL(request.url);
  const { lang, explicit } = chooseLanguage(url, request);
  // Links are https in production; the scheme is fixed so a preview never
  // advertises an http image.
  const origin = `https://${url.host}`;
  const imageUrl = `${origin}${IMAGE_PATH}`;

  const id = typeof rawId === 'string' ? rawId : Array.isArray(rawId) ? rawId[0] : '';
  if (!isUuid(id)) {
    // Not a match id: nothing to look up and nowhere to send anyone.
    const shareUrl = `${origin}/`;
    const html = renderHtml(fallbackMetadata(lang), {
      lang, shareUrl, imageUrl, redirectPath: null, unavailable: true,
    });
    return respond(request, 404, html, 'public, max-age=300');
  }

  const matchId = id.toLowerCase();
  const shareUrl = `${origin}/share/match/${matchId}${explicit ? `?lang=${lang}` : ''}`;
  const redirectPath = `/#/match/${matchId}`;

  const result = await fetchPublicMatch(env, matchId, fetchImpl);
  const meta = result.status === 'ok' ? invitationMetadata(result.row, lang) : null;
  const html = renderHtml(meta ?? fallbackMetadata(lang), {
    lang, shareUrl, imageUrl, redirectPath, unavailable: false,
  });

  // A transient failure must not be remembered; a settled answer may be, briefly.
  const cache = result.status === 'error' || result.status === 'unconfigured'
    ? 'no-store'
    : 'public, max-age=60';
  return respond(request, 200, html, cache);
}

export const onRequest = (context) => handle(context.request, context.env, context.params?.id);
