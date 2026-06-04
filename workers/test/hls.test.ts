import { describe, expect, it } from 'vitest';
import { isMediaPlaylist, rewriteUris, stripAds } from '../src/hls';

describe('stripAds', () => {
  it('drops a stitched-ad DATERANGE and its bracketed segments', () => {
    const input = [
      '#EXTM3U',
      '#EXT-X-VERSION:6',
      '#EXT-X-TARGETDURATION:2',
      '#EXT-X-MEDIA-SEQUENCE:100',
      '#EXTINF:2.000,live',
      'seg0.ts',
      '#EXT-X-DATERANGE:ID="stitched-ad-1234",CLASS="twitch-stitched-ad",START-DATE="2024-01-01T00:00:00Z",DURATION=15.0',
      '#EXT-X-DISCONTINUITY',
      '#EXTINF:5.000,Amazon|something',
      'ad0.ts',
      '#EXTINF:5.000,Amazon|something',
      'ad1.ts',
      '#EXT-X-DISCONTINUITY',
      '#EXTINF:2.000,live',
      'seg1.ts',
      '#EXTINF:2.000,live',
      'seg2.ts',
    ].join('\n');

    const out = stripAds(input);

    expect(out).not.toContain('ad0.ts');
    expect(out).not.toContain('ad1.ts');
    expect(out).not.toContain('twitch-stitched-ad');
    expect(out).not.toContain('Amazon');
    expect(out).toContain('seg0.ts');
    expect(out).toContain('seg1.ts');
    expect(out).toContain('seg2.ts');
    expect(out).not.toContain('#EXT-X-DISCONTINUITY');
    expect(out).toContain('#EXT-X-MEDIA-SEQUENCE:100');
    expect(out).toContain('#EXT-X-TARGETDURATION:2');
  });

  it('drops segments whose EXTINF title contains Amazon even without a DATERANGE', () => {
    const input = [
      '#EXTM3U',
      '#EXTINF:2.000,live',
      'seg0.ts',
      '#EXTINF:15.000,Amazon Prime',
      'ad.ts',
      '#EXTINF:2.000,live',
      'seg1.ts',
    ].join('\n');

    const out = stripAds(input);
    const lines = out.split('\n').filter((l) => l.length > 0);

    expect(out).not.toContain('ad.ts');
    expect(out).not.toContain('Amazon');
    expect(lines.filter((l) => l.endsWith('.ts'))).toEqual(['seg0.ts', 'seg1.ts']);
  });

  it('preserves EXT-X-TWITCH-PREFETCH low-latency tags', () => {
    const input = [
      '#EXTM3U',
      '#EXTINF:2.000,live',
      'seg0.ts',
      '#EXT-X-TWITCH-PREFETCH:https://video.example/low-latency-seg.ts',
    ].join('\n');

    const out = stripAds(input);
    expect(out).toContain('#EXT-X-TWITCH-PREFETCH:https://video.example/low-latency-seg.ts');
    expect(out).toContain('seg0.ts');
  });

  it('leaves a clean playlist untouched in structure', () => {
    const input = [
      '#EXTM3U',
      '#EXT-X-VERSION:6',
      '#EXT-X-TARGETDURATION:2',
      '#EXTINF:2.000,live',
      'seg0.ts',
      '#EXTINF:2.000,live',
      'seg1.ts',
    ].join('\n');

    const out = stripAds(input);
    expect(out).toBe(input);
  });

  it('removes the per-segment PROGRAM-DATE-TIME of a dropped ad segment', () => {
    const input = [
      '#EXTM3U',
      '#EXT-X-PROGRAM-DATE-TIME:2024-01-01T00:00:00Z',
      '#EXTINF:2.000,live',
      'seg0.ts',
      '#EXT-X-PROGRAM-DATE-TIME:2024-01-01T00:00:02Z',
      '#EXTINF:2.000,Amazon|123',
      'ad0.ts',
      '#EXT-X-PROGRAM-DATE-TIME:2024-01-01T00:00:04Z',
      '#EXTINF:2.000,live',
      'seg1.ts',
    ].join('\n');

    const out = stripAds(input);
    expect(out).not.toContain('ad0.ts');
    expect(out).not.toContain('2024-01-01T00:00:02Z');
    expect(out).toContain('2024-01-01T00:00:00Z');
    expect(out).toContain('2024-01-01T00:00:04Z');
    expect(out.split('\n').filter((l) => l.startsWith('#EXT-X-PROGRAM-DATE-TIME'))).toHaveLength(2);
  });

  it('matches ad DATERANGE by ID prefix when CLASS is absent', () => {
    const input = [
      '#EXTM3U',
      '#EXT-X-DATERANGE:ID="stitched-ad-99",START-DATE="2024-01-01T00:00:00Z"',
      '#EXTINF:10.000,blank',
      'ad.ts',
      '#EXTINF:2.000,live',
      'seg0.ts',
    ].join('\n');

    const out = stripAds(input);
    expect(out).not.toContain('ad.ts');
    expect(out).not.toContain('stitched-ad-99');
    expect(out).toContain('seg0.ts');
  });
});

describe('isMediaPlaylist', () => {
  it('detects media playlists via EXTINF', () => {
    expect(isMediaPlaylist('#EXTM3U\n#EXTINF:2.0,\nseg.ts')).toBe(true);
  });

  it('treats master playlists as non-media', () => {
    const master = [
      '#EXTM3U',
      '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720',
      'chunked/index.m3u8',
    ].join('\n');
    expect(isMediaPlaylist(master)).toBe(false);
  });
});

describe('rewriteUris', () => {
  const base = 'https://usher.ttvnw.net/api/channel/hls/foo.m3u8';
  const proxyBase = 'https://embr.example.workers.dev/hls/proxy';

  it('rewrites bare variant URIs through the proxy as absolute URLs', () => {
    const master = [
      '#EXTM3U',
      '#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720',
      'https://video-weaver.example/720p.m3u8',
    ].join('\n');

    const out = rewriteUris(master, base, proxyBase);
    const expected = `${proxyBase}?src=${encodeURIComponent('https://video-weaver.example/720p.m3u8')}`;
    expect(out).toContain(expected);
    expect(out).toContain('#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720');
  });

  it('resolves relative segment URIs against the base before proxying', () => {
    const media = [
      '#EXTM3U',
      '#EXTINF:2.0,live',
      'seg0.ts',
    ].join('\n');

    const out = rewriteUris(media, base, proxyBase);
    const abs = 'https://usher.ttvnw.net/api/channel/hls/seg0.ts';
    expect(out).toContain(`${proxyBase}?src=${encodeURIComponent(abs)}`);
  });

  it('rewrites EXT-X-TWITCH-PREFETCH targets through the proxy', () => {
    const media = '#EXTM3U\n#EXT-X-TWITCH-PREFETCH:https://video.example/p.ts';
    const out = rewriteUris(media, base, proxyBase);
    const abs = 'https://video.example/p.ts';
    expect(out).toContain(`#EXT-X-TWITCH-PREFETCH:${proxyBase}?src=${encodeURIComponent(abs)}`);
  });

  it('rewrites URI attributes on MAP/MEDIA tags', () => {
    const media = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:2.0,\nseg.ts';
    const out = rewriteUris(media, base, proxyBase);
    const abs = 'https://usher.ttvnw.net/api/channel/hls/init.mp4';
    expect(out).toContain(`URI="${proxyBase}?src=${encodeURIComponent(abs)}"`);
  });

  it('absolutizes media-playlist segments without proxying when proxyBase is null', () => {
    const media = [
      '#EXTM3U',
      '#EXT-X-MAP:URI="init.mp4"',
      '#EXTINF:2.0,live',
      'seg0.ts',
      '#EXT-X-TWITCH-PREFETCH:https://video.example/p.ts',
    ].join('\n');

    const out = rewriteUris(media, base, null);
    expect(out).toContain('https://usher.ttvnw.net/api/channel/hls/seg0.ts');
    expect(out).toContain('URI="https://usher.ttvnw.net/api/channel/hls/init.mp4"');
    expect(out).toContain('#EXT-X-TWITCH-PREFETCH:https://video.example/p.ts');
    expect(out).not.toContain('/hls/proxy');
  });
});
