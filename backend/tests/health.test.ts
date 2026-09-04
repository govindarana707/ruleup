import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

describe('GET /health', () => {
  it('reports that the Worker is healthy', async () => {
    const response = await SELF.fetch('https://ruleup.local/health');

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('application/json');
    await expect(response.json()).resolves.toEqual({ status: 'ok' });
  });
});
