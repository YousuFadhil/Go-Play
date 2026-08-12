// Template for the Firebase Messaging service worker.
//
// **This file is not the service worker.** `tool/generate_firebase_sw.dart`
// reads it, substitutes the `__PLACEHOLDER__` values, and writes
// `web/firebase-messaging-sw.js` — which is gitignored, for the same reason
// `android/app/google-services.json` is. Only the template is committed, and
// the template names no project.
//
// It sits in `tool/` and not beside its output because `flutter build web`
// copies `web/` verbatim: a template kept there would be published to the site
// root next to the file generated from it.
//
// Run the generator before every `flutter run -d chrome` and every
// `flutter build web`:
//
//   dart run tool/generate_firebase_sw.dart \
//     --api-key=... --app-id=... --sender-id=... --project-id=...
//
// or with the same names as the `--dart-define`s already in the environment
// (`FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID`,
// `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`,
// `FIREBASE_AUTH_DOMAIN`), which is how CI calls it. Without the generated
// file `getToken` fails: the browser 404s on the registration and the SDK
// cannot subscribe to Web Push.
//
// ---------------------------------------------------------------------------
// Why the name and the location are not a choice
//
// `getToken()` does not take a service worker from the caller. It registers
// `/firebase-messaging-sw.js` under the scope
// `/firebase-cloud-messaging-push-scope` and subscribes *that* registration —
// so the worker `getToken` uses is this file, at the site root, by virtue of
// being there. Move it, rename it, or serve the app under a sub-path and the
// SDK looks somewhere else.
//
// Why the SDK is loaded here
//
// The worker is what receives the push. `firebase.messaging()` installs the
// handlers that make the two documented behaviours work:
//
//   * app closed or the tab hidden — the notification is drawn from the
//     `notification` block `push-dispatch` sends;
//   * a tab visible — nothing is drawn, and the message is forwarded to the
//     page instead, which is what makes `FirebaseMessaging.onMessage` fire and
//     `PushService.foregroundPushes` tick.
//
// The second one is only reachable through the SDK: that forwarding is an
// internal message between the SDK's worker and the SDK in the page.
//
// The SDK version is pinned to the one `firebase_core_web` injects into the
// page (`supportedFirebaseJsSdkVersion`). Two versions in one origin is a
// combination nobody tests.
//
// Clicking a notification is handled by the SDK too, and it opens
// `webpush.fcm_options.link` — which `push-dispatch` sets from
// `PUSH_WEB_APP_URL`. A custom `notificationclick` listener here would not be
// an alternative: the SDK's own listener is registered first and calls
// `stopImmediatePropagation`, so nothing added below it would ever run. If
// clicks should open the app, that secret is what sets it.

importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '__FIREBASE_WEB_API_KEY__',
  appId: '__FIREBASE_WEB_APP_ID__',
  messagingSenderId: '__FIREBASE_MESSAGING_SENDER_ID__',
  projectId: '__FIREBASE_PROJECT_ID__',
  authDomain: '__FIREBASE_AUTH_DOMAIN__',
});

// The whole point of the file. Constructing the messaging instance is what
// registers the `push` and `notificationclick` handlers in this worker; there
// is nothing to call on the result, and no background handler to add.
//
// Deliberately no `onBackgroundMessage`: registering one *replaces* the default
// display, and the default display is exactly what is wanted. Every push this
// system sends carries a `notification` block, and the notice it reports is
// already committed to the Notification Center.
firebase.messaging();
