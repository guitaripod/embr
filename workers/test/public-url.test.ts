import { describe, expect, it } from 'vitest';
import { publicBase, publicPrefix } from '../src/public-url';

describe('publicPrefix', () => {
  it('accepts the gateway mount and plain nested paths', () => {
    expect(publicPrefix('/v1/embr')).toBe('/v1/embr');
    expect(publicPrefix(' /v1/embr/ ')).toBe('/v1/embr');
    expect(publicPrefix('/a.b/c_d~e-f')).toBe('/a.b/c_d~e-f');
  });

  it('is empty without a header or with anything that is not a safe path', () => {
    const bad = [undefined, '', '   ', '/', '//', 'v1/embr', '/v1//embr', '/v1/../embr', '/./x', '/v1/embr?x=1', '/v1/embr#f', '/v1/em br', 'https://x.example/v1', `/${'a'.repeat(200)}`];
    for (const value of bad) expect(publicPrefix(value), String(value)).toBe('');
  });
});

describe('publicBase', () => {
  it('joins the request origin and the prefix', () => {
    expect(publicBase('https://api.midgarcorp.cc/playback/x?y=1', '/v1/embr')).toBe('https://api.midgarcorp.cc/v1/embr');
  });

  it('is the origin alone without a usable prefix', () => {
    expect(publicBase('https://embr.guitaripod.workers.dev/playback/x', undefined)).toBe('https://embr.guitaripod.workers.dev');
    expect(publicBase('http://embr.test:8787/x', '/..')).toBe('http://embr.test:8787');
  });
});
