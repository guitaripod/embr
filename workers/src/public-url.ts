export const FORWARDED_PREFIX_HEADER = 'X-Forwarded-Prefix';

const MAX_PREFIX_LENGTH = 128;
const PREFIX_SEGMENT_RE = /^[A-Za-z0-9._~-]+$/;

/**
 * The path the gateway mounts this worker at (`/v1/embr`), read from `X-Forwarded-Prefix`. Anything that is
 * not a plain run of safe path segments, such as an empty value, a dot segment, a query or a scheme, yields
 * an empty prefix, so a worker reached directly on its own host keeps building links from the host alone.
 */
export function publicPrefix(header: string | undefined): string {
  if (header === undefined) return '';
  const value = header.trim().replace(/\/+$/, '');
  if (value === '' || value.length > MAX_PREFIX_LENGTH || !value.startsWith('/')) return '';
  const segments = value.slice(1).split('/');
  const safe = segments.every((segment) => PREFIX_SEGMENT_RE.test(segment) && !/^\.+$/.test(segment));
  return safe ? value : '';
}

/**
 * The origin and prefix that links to this worker must carry to reach it again from outside:
 * `https://api.midgarcorp.cc/v1/embr` behind the gateway, the request origin alone otherwise.
 */
export function publicBase(requestURL: string, prefixHeader: string | undefined): string {
  return `${new URL(requestURL).origin}${publicPrefix(prefixHeader)}`;
}
