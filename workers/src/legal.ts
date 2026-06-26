const SUPPORT_EMAIL = 'guitaripod@gmail.com';
const UPDATED = '2026-06-26';

function page(title: string, bodyHTML: string): Response {
  const html =
    `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width, initial-scale=1">` +
    `<title>${title} · Embr</title>` +
    `<style>:root{color-scheme:light dark}body{font:16px/1.6 -apple-system,system-ui,sans-serif;` +
    `max-width:46rem;margin:0 auto;padding:2rem 1.25rem;color:#1c1c1e;background:#fff}` +
    `@media(prefers-color-scheme:dark){body{color:#e5e5ea;background:#000}}` +
    `h1{font-size:1.7rem}h2{font-size:1.2rem;margin-top:2rem}a{color:#9147ff}` +
    `small{color:#8e8e93}</style></head><body>${bodyHTML}` +
    `<p><small>Last updated ${UPDATED}. Contact: <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a></small></p>` +
    `</body></html>`;
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=3600' },
  });
}

export function termsPage(): Response {
  return page(
    'Terms of Use',
    `<h1>Embr — Terms of Use</h1>` +
      `<p>Embr is an independent, open-source client for watching Twitch streams and chat. ` +
      `It is not affiliated with, endorsed by, or sponsored by Twitch Interactive, Inc. ` +
      `By using Embr you agree to these terms and to Twitch's own Terms of Service and Community Guidelines.</p>` +
      `<h2>User-generated content</h2>` +
      `<p>Embr displays live chat and other content created by Twitch users. Embr does not create, ` +
      `endorse, or control that content. <strong>There is zero tolerance for objectionable content or ` +
      `abusive behaviour.</strong> You may report any message from within the app, and you may block or ` +
      `hide any user. Reported content and users are reviewed, and offending users may be ejected from ` +
      `the service. Twitch's own moderation and reporting tools also apply.</p>` +
      `<h2>Acceptable use</h2>` +
      `<p>Do not use Embr to harass, threaten, or abuse others, to post unlawful content, or to ` +
      `circumvent Twitch's terms. Streams play through Twitch's official embedded player, including any ` +
      `advertising Twitch serves.</p>` +
      `<h2>No warranty</h2>` +
      `<p>Embr is provided "as is", without warranty of any kind. Availability depends on Twitch's ` +
      `services and may change at any time.</p>`,
  );
}

export function privacyPage(): Response {
  return page(
    'Privacy Policy',
    `<h1>Embr — Privacy Policy</h1>` +
      `<p>Embr is designed to collect as little data as possible. The developer does not operate any ` +
      `advertising or analytics tracking, and does not sell or share your data.</p>` +
      `<h2>What stays on your device</h2>` +
      `<p>Your settings, watch history, list of channels, and blocked/hidden users are stored only on ` +
      `your device. Diagnostic logs are written to the app's private storage and never leave your device ` +
      `unless you explicitly choose to share them.</p>` +
      `<h2>Sign in with Twitch</h2>` +
      `<p>If you choose to sign in, authentication happens through Twitch's official OAuth flow. Your ` +
      `Twitch access token is stored in the device Keychain and is sent only to Twitch's own APIs (via a ` +
      `thin proxy that holds no copy of it) to load chat and your follows. You can log out at any time, ` +
      `which removes the token from your device.</p>` +
      `<h2>Reports</h2>` +
      `<p>When you report a chat message, the reported message, its author, and your selected reason are ` +
      `sent to the developer so the report can be reviewed. Reports do not include your identity.</p>` +
      `<h2>Twitch</h2>` +
      `<p>Video and chat come from Twitch. Twitch's own privacy policy governs the data Twitch collects ` +
      `when its embedded player and services are used.</p>`,
  );
}
