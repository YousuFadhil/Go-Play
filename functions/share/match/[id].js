// Both existing Wrangler workflows deploy from the repository root, where
// Pages discovers /functions. _routes.json invokes it only for match sharing.
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const copy = {
  ar: { title: 'Go Play — دعوة إلى مباراة', description: 'افتح المباراة في Go Play لاستكمال التسجيل.', location: 'الموقع', open: 'فتح المباراة في Go Play', invite: '⚽ انضم إلى', action: 'افتح الرابط لعرض التفاصيل والانضمام' },
  en: { title: 'Go Play — Match invitation', description: 'Open the match in Go Play to continue registration.', location: 'Location', open: 'Open match in Go Play', invite: '⚽ Join', action: 'Open the link to view details and join' },
};
const thumbnails = {
  ar: { file: 'go-play-invite-v2-ar.png', width: 1730, height: 909 },
  en: { file: 'go-play-invite-v2-en.png', width: 1731, height: 909 },
};
const neutralThumbnail = { file: 'go-play-thumbnail.png', width: 1200, height: 630 };

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function text(value, maxLength = 200) {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

// Fail closed if configuration accidentally supplies a privileged key.
function publicKey(key) {
  if (typeof key !== 'string') return false;
  if (/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) return true;
  try {
    const payload = key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(payload)).role === 'anon';
  } catch { return false; }
}

function description(match, language) {
  const locale = language === 'en' ? 'en-GB' : 'ar-OM';
  const start = new Date(match.start_at);
  const end = new Date(match.end_at);
  const parts = [];
  if (Number.isFinite(start.getTime())) {
    parts.push(new Intl.DateTimeFormat(locale, {
      timeZone: 'Asia/Muscat', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric',
    }).format(start));
    const time = new Intl.DateTimeFormat(locale, {
      timeZone: 'Asia/Muscat', hour: 'numeric', minute: '2-digit', hour12: true,
    });
    // Isolates keep the Arabic time range in reading order.
    parts.push(`\u2068${time.format(start)}\u2069${Number.isFinite(end.getTime()) ? ` – \u2068${time.format(end)}\u2069` : ''}`);
  }
  const location = text(match.location, 160);
  if (location) parts.push(`${copy[language].location}: ${location}`);
  return parts.join(' • ') || copy[language].description;
}

export async function onRequest({ request, params, env }) {
  if (!['GET', 'HEAD'].includes(request.method)) {
    return new Response(null, { status: 405, headers: { Allow: 'GET, HEAD' } });
  }
  const url = new URL(request.url);
  const language = url.searchParams.get('lang') === 'en' ? 'en' : 'ar';
  const words = copy[language];
  const valid = typeof params.id === 'string' && uuid.test(params.id);
  const id = valid ? params.id.toLowerCase() : '';
  const version = url.searchParams.get('v') === '2' ? '&v=2' : '';
  const canonical = `${url.origin}/share/match/${id}?lang=${language}${version}`;
  const destination = valid ? `${url.origin}/#/match/${id}` : `${url.origin}/`;
  let thumbnail = neutralThumbnail;
  let title = words.title;
  let summary = words.description;
  let status = valid ? 503 : 400;

  if (valid && publicKey(env.SUPABASE_ANON_KEY)) {
    try {
      const base = new URL(env.SUPABASE_URL);
      if (base.protocol !== 'https:' || base.pathname !== '/' || base.search || base.hash || base.username || base.password) {
        throw new Error('Invalid public API base');
      }
      const key = env.SUPABASE_ANON_KEY;
      const response = await fetch(`${base.origin}/rest/v1/rpc/public_match_detail`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json', apikey: key,
          ...(key.startsWith('sb_publishable_') ? {} : { Authorization: `Bearer ${key}` }),
        },
        body: JSON.stringify({ p_match_id: id }),
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) throw new Error('Public match unavailable');
      const rows = await response.json();
      if (!Array.isArray(rows)) throw new Error('Unexpected public response');
      const match = rows.find(row => row && row.match_id === id);
      status = match ? 200 : 404;
      if (match) {
        const name = text(match.title) || text(match.location);
        const upcoming = match.public_state !== 'COMPLETED';
        if (upcoming) thumbnail = thumbnails[language];
        title = name ? `${upcoming ? `${words.invite} ` : ''}${name} — Go Play` : words.title;
        summary = description(match, language);
        if (upcoming) summary += ` • ${words.action}`;
      }
    } catch {
      // No API errors, credentials, roster or session details reach the page.
      status = 503;
    }
  }

  const image = `${url.origin}/share/${thumbnail.file}`;
  // Keep an HTML document for crawlers rather than an HTTP redirect to Flutter.
  // Human navigation uses the existing route; the link also works without JS.
  const html = `<!doctype html>
<html lang="${language}" dir="${language === 'ar' ? 'rtl' : 'ltr'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(summary)}">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(summary)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Go Play">
<meta property="og:locale" content="${language === 'ar' ? 'ar_OM' : 'en_GB'}">
<meta property="og:url" content="${escapeHtml(canonical)}">
<meta property="og:image" content="${escapeHtml(image)}">
<meta property="og:image:secure_url" content="${escapeHtml(image)}">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="${thumbnail.width}">
<meta property="og:image:height" content="${thumbnail.height}">
<meta property="og:image:alt" content="Go Play">
<meta name="twitter:card" content="summary_large_image">
<link rel="canonical" href="${escapeHtml(canonical)}">
</head>
<body>
<h1>${escapeHtml(title)}</h1>
<p>${escapeHtml(summary)}</p>
<a id="open-match" href="${escapeHtml(destination)}">${words.open}</a>
<script>location.replace(document.getElementById('open-match').href);</script>
</body>
</html>`;
  return new Response(request.method === 'HEAD' ? null : html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
    },
  });
}
