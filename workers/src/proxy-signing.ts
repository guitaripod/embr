export const PROXY_SIGNATURE_TTL_SECONDS = 24 * 60 * 60;

export interface ProxySignature {
  exp: number;
  sig: string;
}

const encoder = new TextEncoder();
const EXP_PATTERN = /^\d{1,12}$/;
const SIG_PATTERN = /^[0-9a-f]{64}$/;

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

/// The MAC covers the expiry as well as the URL, so a signature cannot be reused for another
/// `src` or extended past its `exp`. The newline separator keeps the two fields unambiguous.
function signedMessage(src: string, exp: number): Uint8Array {
  return encoder.encode(`${exp}\n${src}`);
}

function importKey(secret: string, usage: 'sign' | 'verify'): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [usage]);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

/// Mints `exp` and `sig` for a proxied `src`, valid for PROXY_SIGNATURE_TTL_SECONDS from `now`.
export async function signProxySrc(secret: string, src: string, now: number): Promise<ProxySignature> {
  const exp = now + PROXY_SIGNATURE_TTL_SECONDS;
  const mac = await crypto.subtle.sign('HMAC', await importKey(secret, 'sign'), signedMessage(src, exp));
  return { exp, sig: bytesToHex(new Uint8Array(mac)) };
}

/// Checks the signature with `crypto.subtle.verify`, which compares in constant time. Rejects
/// malformed, expired, and over-long-lived values before the MAC is even computed.
export async function isValidProxySignature(
  secret: string,
  src: string,
  exp: string | null,
  sig: string | null,
  now: number,
): Promise<boolean> {
  if (exp === null || sig === null || !EXP_PATTERN.test(exp) || !SIG_PATTERN.test(sig)) return false;
  const expiresAt = Number(exp);
  if (expiresAt < now || expiresAt - now > PROXY_SIGNATURE_TTL_SECONDS) return false;
  return crypto.subtle.verify('HMAC', await importKey(secret, 'verify'), hexToBytes(sig), signedMessage(src, expiresAt));
}
