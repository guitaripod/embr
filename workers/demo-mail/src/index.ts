import PostalMime from "postal-mime";

interface Env {
  MAIL: KVNamespace;
}

const PATH_TOKEN = "4bf7008a3c55211fa003cb13";

interface StoredMail {
  from: string;
  subject: string;
  text: string;
  code: string | null;
  receivedAt: string;
}

function extractCode(subject: string, text: string): string | null {
  const haystacks = [subject, text];
  for (const h of haystacks) {
    const m = h.match(/\b(\d{6,8})\b/);
    if (m) return m[1];
  }
  return null;
}

export default {
  async email(message, env, ctx): Promise<void> {
    const raw = await new Response(message.raw).arrayBuffer();
    const parsed = await PostalMime.parse(raw);
    const subject = parsed.subject ?? "(no subject)";
    const text = parsed.text ?? parsed.html?.replace(/<[^>]+>/g, " ") ?? "";
    const stored: StoredMail = {
      from: message.from,
      subject,
      text: text.slice(0, 4000),
      code: extractCode(subject, text),
      receivedAt: new Date().toISOString(),
    };
    await env.MAIL.put("latest", JSON.stringify(stored));
    await env.MAIL.put(`mail:${Date.now()}`, JSON.stringify(stored), {
      expirationTtl: 60 * 60 * 24 * 14,
    });
  },

  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== `/code/${PATH_TOKEN}`) {
      return new Response("Not found", { status: 404 });
    }
    const latestRaw = await env.MAIL.get("latest");
    if (!latestRaw) {
      return html(
        "No email received yet",
        "<p>No email has arrived for the demo account yet. Request the verification code in the Twitch sign-in flow, wait ~30 seconds, then refresh this page.</p>",
      );
    }
    const latest: StoredMail = JSON.parse(latestRaw);
    const codeBlock = latest.code
      ? `<p>Verification code:</p><div class="code">${latest.code}</div>`
      : "<p>No numeric code detected in the latest email; full text below.</p>";
    return html(
      "Embr demo account — latest email",
      `${codeBlock}
       <p class="meta">Received ${latest.receivedAt} · From ${escapeHtml(latest.from)}<br>Subject: ${escapeHtml(latest.subject)}</p>
       <details><summary>Full email text</summary><pre>${escapeHtml(latest.text)}</pre></details>
       <p class="meta">Refresh this page after requesting a new code.</p>`,
    );
  },
} satisfies ExportedHandler<Env>;

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function html(title: string, body: string): Response {
  return new Response(
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>${title}</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 20px;color:#111}
.code{font-size:44px;font-weight:700;letter-spacing:6px;background:#f4f4f5;border-radius:12px;padding:20px;text-align:center;margin:16px 0}
.meta{color:#666;font-size:14px}pre{white-space:pre-wrap;background:#f9f9fa;padding:12px;border-radius:8px}</style>
</head><body><h2>${title}</h2>${body}</body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } },
  );
}
