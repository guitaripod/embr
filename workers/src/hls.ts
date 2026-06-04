const STITCHED_AD_CLASS = 'twitch-stitched-ad';
const STITCHED_AD_ID_PREFIX = 'stitched-ad-';

function attribute(line: string, key: string): string | undefined {
  const re = new RegExp(`${key}="([^"]*)"|${key}=([^,\\s]+)`);
  const m = re.exec(line);
  if (!m) return undefined;
  return m[1] ?? m[2];
}

function isStitchedAdDaterange(line: string): boolean {
  if (!line.startsWith('#EXT-X-DATERANGE')) return false;
  if (attribute(line, 'CLASS') === STITCHED_AD_CLASS) return true;
  const id = attribute(line, 'ID');
  return id !== undefined && id.startsWith(STITCHED_AD_ID_PREFIX);
}

function extinfTitle(line: string): string {
  const comma = line.indexOf(',');
  return comma === -1 ? '' : line.slice(comma + 1);
}

function isContentTitle(title: string): boolean {
  const trimmed = title.trim();
  return trimmed.length > 0 && !trimmed.includes('Amazon');
}

function nextSegmentURIIndex(lines: string[], from: number): number {
  let j = from;
  while (j < lines.length) {
    const next = (lines[j] ?? '').replace(/\r$/, '');
    if (next.startsWith('#')) return j;
    if (next.trim().length > 0) return j + 1;
    j += 1;
  }
  return j;
}

/// Removes Twitch stitched-ad segments from a media playlist while keeping it valid.
///
/// Drops `#EXT-X-DATERANGE` ad markers (CLASS="twitch-stitched-ad" or ID prefixed
/// "stitched-ad-"), the `#EXTINF` segments inside the ad window or whose title
/// contains "Amazon" (plus the following URI line), and the `#EXT-X-DISCONTINUITY`
/// tags bracketing the ad block. The window is opened by the ad marker and closed
/// by the first content segment (a non-empty, non-"Amazon" `#EXTINF` title) or the
/// closing discontinuity. Preserves `#EXT-X-TWITCH-PREFETCH` low-latency tags.
export function stripAds(playlist: string): string {
  const lines = playlist.split('\n');
  const out: string[] = [];

  let inAdWindow = false;
  let consumedFirstAdSegment = false;
  let droppedSomething = false;

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i] ?? '';
    const line = raw.replace(/\r$/, '');

    if (isStitchedAdDaterange(line)) {
      inAdWindow = true;
      consumedFirstAdSegment = false;
      droppedSomething = true;
      continue;
    }

    if (line.startsWith('#EXT-X-DISCONTINUITY')) {
      if (inAdWindow) {
        droppedSomething = true;
        continue;
      }
      out.push(raw);
      continue;
    }

    if (line.startsWith('#EXTINF')) {
      const title = extinfTitle(line);
      const amazon = title.includes('Amazon');
      if (inAdWindow && consumedFirstAdSegment && isContentTitle(title)) {
        inAdWindow = false;
      }
      const isAd = amazon || inAdWindow;
      if (isAd) {
        while (out.length > 0 && (out[out.length - 1] ?? '').replace(/\r$/, '').startsWith('#EXT-X-PROGRAM-DATE-TIME')) {
          out.pop();
        }
        const uriEnd = nextSegmentURIIndex(lines, i + 1);
        i = uriEnd - 1;
        consumedFirstAdSegment = true;
        droppedSomething = true;
        continue;
      }
      out.push(raw);
      continue;
    }

    if (line.startsWith('#EXT-X-TWITCH-PREFETCH')) {
      inAdWindow = false;
      out.push(raw);
      continue;
    }

    if (line.length === 0) {
      out.push(raw);
      continue;
    }

    inAdWindow = false;
    out.push(raw);
  }

  return droppedSomething ? out.join('\n') : playlist;
}

/// True when the playlist is a media playlist (segments) rather than a master playlist (variants).
export function isMediaPlaylist(playlist: string): boolean {
  return (
    playlist.includes('#EXTINF') ||
    playlist.includes('#EXT-X-TARGETDURATION') ||
    playlist.includes('#EXT-X-MEDIA-SEQUENCE')
  );
}

function resolveURI(uri: string, base: string): string {
  try {
    return new URL(uri, base).toString();
  } catch {
    return uri;
  }
}

function proxied(absoluteURI: string, proxyBase: string | null): string {
  return proxyBase === null ? absoluteURI : `${proxyBase}?src=${encodeURIComponent(absoluteURI)}`;
}

const URI_ATTR_TAGS = ['#EXT-X-MEDIA', '#EXT-X-MAP', '#EXT-X-KEY', '#EXT-X-PART', '#EXT-X-PRELOAD-HINT'];

function rewriteUriAttribute(line: string, base: string, proxyBase: string | null): string {
  return line.replace(/URI="([^"]*)"/g, (_full, uri: string) => {
    const abs = resolveURI(uri, base);
    return `URI="${proxied(abs, proxyBase)}"`;
  });
}

/// Rewrites child playlist/segment references in an HLS playlist.
///
/// `base` resolves relative URIs to absolute upstream URLs. When `proxyBase` is a
/// string, references are routed back through this worker's `/hls/proxy` endpoint
/// (used for master playlists so each variant's media playlist gets ad-stripped).
/// When `proxyBase` is `null`, references are only made absolute and point straight
/// at Twitch's CDN (used for media playlists so binary segments download directly
/// instead of being corrupted by a text-mode proxy round-trip).
/// Handles bare URI lines, `#EXT-X-TWITCH-PREFETCH` targets, and `URI="..."`
/// attributes on MEDIA/MAP/KEY/PART tags.
export function rewriteUris(playlist: string, base: string, proxyBase: string | null): string {
  const lines = playlist.split('\n');
  const out: string[] = [];

  for (const raw of lines) {
    const line = raw.replace(/\r$/, '');

    if (line.length === 0) {
      out.push(raw);
      continue;
    }

    if (line.startsWith('#EXT-X-TWITCH-PREFETCH:')) {
      const uri = line.slice('#EXT-X-TWITCH-PREFETCH:'.length).trim();
      const abs = resolveURI(uri, base);
      out.push(`#EXT-X-TWITCH-PREFETCH:${proxied(abs, proxyBase)}`);
      continue;
    }

    if (URI_ATTR_TAGS.some((tag) => line.startsWith(tag))) {
      out.push(rewriteUriAttribute(line, base, proxyBase));
      continue;
    }

    if (line.startsWith('#')) {
      out.push(raw);
      continue;
    }

    const abs = resolveURI(line.trim(), base);
    out.push(proxied(abs, proxyBase));
  }

  return out.join('\n');
}
