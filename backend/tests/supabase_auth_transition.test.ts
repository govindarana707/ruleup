import { describe, expect, it } from 'vitest';
import { handleLogin } from '../src/auth/routes';
import {
  HttpSupabaseAuthAdmin,
  SupabaseAdminError,
  syntheticAuthEmail,
  type LegacyIdentity,
  type SupabaseAuthAdmin,
  type SupabaseSessionPayload,
} from '../src/supabase/admin';
import { transitionSupabaseAuth } from '../src/auth/supabase_transition';
import { testEnv } from './setup';

const userId = '11111111-1111-4111-8111-111111111111';
const password = 'correct-horse-battery-staple';
const session: SupabaseSessionPayload = {
  accessToken: 'supabase-access',
  refreshToken: 'supabase-refresh',
  expiresAt: 2_000_000_000,
  userId,
};

describe('Supabase auth identity bridge', () => {
  it('uses an immutable synthetic email derived only from the legacy UUID', () => {
    expect(syntheticAuthEmail(userId)).toBe(
      '11111111-1111-4111-8111-111111111111@auth.ruleup.invalid',
    );
    expect(() => syntheticAuthEmail('attacker-controlled')).toThrow(
      SupabaseAdminError,
    );
  });

  it('sends the exact legacy UUID and matching profile ID', async () => {
    const requests: Array<{ url: URL; body: Record<string, unknown> }> = [];
    const fetcher: typeof fetch = async (input, init) => {
      const url = new URL(input.toString());
      const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
      requests.push({ url, body });
      if (url.pathname === '/auth/v1/admin/users') {
        return Response.json({
          id: userId,
          email: syntheticAuthEmail(userId),
          app_metadata: {
            identity_source: 'ruleup_legacy',
            legacy_user_id: userId,
          },
        });
      }
      return new Response(null, { status: 201 });
    };
    const admin = new HttpSupabaseAuthAdmin(
      new URL('https://project.supabase.co'),
      'server-only-secret',
      fetcher,
    );

    await admin.ensureLegacyIdentity({ id: userId, username: 'tester' }, password);

    expect(requests[0].body.id).toBe(userId);
    expect(requests[1].body).toMatchObject({ id: userId, username: 'tester' });
    expect(JSON.stringify(requests)).not.toContain('server-only-secret');
  });

  it('reconciles an exact duplicate instead of creating another identity', async () => {
    const methods: string[] = [];
    const fetcher: typeof fetch = async (input, init) => {
      const url = new URL(input.toString());
      methods.push(`${init?.method ?? 'GET'} ${url.pathname}`);
      if (url.pathname === '/auth/v1/admin/users' && init?.method === 'POST') {
        return Response.json({}, { status: 422 });
      }
      if (url.pathname === `/auth/v1/admin/users/${userId}` && !init?.method) {
        return Response.json({
          id: userId,
          email: syntheticAuthEmail(userId),
          app_metadata: {
            identity_source: 'ruleup_legacy',
            legacy_user_id: userId,
          },
        });
      }
      return new Response(null, { status: 200 });
    };
    const admin = new HttpSupabaseAuthAdmin(
      new URL('https://project.supabase.co'),
      'secret',
      fetcher,
    );

    await admin.ensureLegacyIdentity({ id: userId, username: 'tester' }, password);

    expect(methods.filter((value) => value === 'POST /auth/v1/admin/users')).toHaveLength(1);
    expect(methods).toContain(`PUT /auth/v1/admin/users/${userId}`);
  });

  it('does not overwrite an unrelated identity occupying the UUID', async () => {
    const fetcher: typeof fetch = async (input, init) => {
      if (init?.method === 'POST') return Response.json({}, { status: 422 });
      return Response.json({
        id: userId,
        email: 'someone@example.com',
        app_metadata: {},
      });
    };
    const admin = new HttpSupabaseAuthAdmin(
      new URL('https://project.supabase.co'),
      'secret',
      fetcher,
    );

    await expect(
      admin.ensureLegacyIdentity({ id: userId, username: 'tester' }, password),
    ).rejects.toMatchObject({ kind: 'identity_conflict' });
  });

  it('skips creation for an already migrated account', async () => {
    const admin = new FakeAdmin();
    const result = await transitionSupabaseAuth(
      admin,
      { id: userId, username: 'tester', authMigratedAt: '2026-09-11T00:00:00Z' },
      password,
    );
    expect(admin.ensureCalls).toBe(0);
    expect(admin.signInCalls).toBe(1);
    expect(result.session?.userId).toBe(userId);
  });

  it('valid legacy credentials migrate, persist state, and preserve UUID', async () => {
    await insertLegacyUser('migrate_me');
    const admin = new FakeAdmin();
    const response = await handleLogin(loginRequest('migrate_me', password), testEnv, admin);
    const body = await response.json<{ data: Record<string, any> }>();
    const stored = await testEnv.DB.prepare(
      'SELECT id, auth_migrated_at, supabase_auth_email FROM users WHERE username = ?',
    ).bind('migrate_me').first<Record<string, string>>();

    expect(response.status).toBe(200);
    expect(body.data.user.id).toBe(userId);
    expect(body.data.supabaseSession.userId).toBe(userId);
    expect(stored?.id).toBe(userId);
    expect(stored?.auth_migrated_at).toBeTruthy();
    expect(stored?.supabase_auth_email).toBe(syntheticAuthEmail(userId));
  });

  it('already migrated login does not recreate identity', async () => {
    await insertLegacyUser('already_migrated');
    await testEnv.DB.prepare(
      'UPDATE users SET auth_migrated_at = ?, supabase_auth_email = ? WHERE id = ?',
    ).bind(
      '2026-09-11T00:00:00.000Z',
      syntheticAuthEmail(userId),
      userId,
    ).run();
    const admin = new FakeAdmin();

    const response = await handleLogin(
      loginRequest('already_migrated', password),
      testEnv,
      admin,
    );

    expect(response.status).toBe(200);
    expect(admin.ensureCalls).toBe(0);
    expect(admin.signInCalls).toBe(1);
  });

  it('does not bypass definitive Supabase invalid credentials after migration', async () => {
    await insertLegacyUser('supabase_password_owner');
    await testEnv.DB.prepare(
      'UPDATE users SET auth_migrated_at = ?, supabase_auth_email = ? WHERE id = ?',
    ).bind(
      '2026-09-11T00:00:00.000Z',
      syntheticAuthEmail(userId),
      userId,
    ).run();
    const admin = new FakeAdmin();
    admin.signInError = new SupabaseAdminError(
      'invalid_credentials',
      'invalid',
    );

    const response = await handleLogin(
      loginRequest('supabase_password_owner', password),
      testEnv,
      admin,
    );

    expect(response.status).toBe(401);
  });

  it('invalid legacy credentials cannot invoke migration or spoof a UUID', async () => {
    await insertLegacyUser('no_migrate');
    const admin = new FakeAdmin();
    const request = new Request('https://ruleup.local/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: 'no_migrate',
        password: 'this-password-is-wrong',
        userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      }),
    });
    const response = await handleLogin(request, testEnv, admin);
    expect(response.status).toBe(401);
    expect(admin.ensureCalls).toBe(0);
    expect(admin.signInCalls).toBe(0);
  });

  it('keeps legacy login usable and retries safely after a partial failure', async () => {
    await insertLegacyUser('retry_user');
    const failing = new FakeAdmin();
    failing.ensureError = new SupabaseAdminError('network', 'temporary');
    const fallback = await handleLogin(loginRequest('retry_user', password), testEnv, failing);
    expect(fallback.status).toBe(200);
    const firstStored = await migrationTimestamp('retry_user');
    expect(firstStored).toBeNull();

    const retry = new FakeAdmin();
    const migrated = await handleLogin(loginRequest('retry_user', password), testEnv, retry);
    expect(migrated.status).toBe(200);
    expect(retry.ensureCalls).toBe(1);
    expect(await migrationTimestamp('retry_user')).toBeTruthy();
  });
});

class FakeAdmin implements SupabaseAuthAdmin {
  ensureCalls = 0;
  signInCalls = 0;
  ensureError: unknown;
  signInError: unknown;

  async ensureLegacyIdentity(
    identity: LegacyIdentity,
    supplied: string,
  ): Promise<void> {
    this.ensureCalls++;
    if (this.ensureError != null) throw this.ensureError;
    expect(identity.id).toBe(userId);
    expect(supplied).toBe(password);
  }

  async signIn(
    identity: LegacyIdentity,
    supplied: string,
  ): Promise<SupabaseSessionPayload> {
    this.signInCalls++;
    if (this.signInError != null) throw this.signInError;
    return session;
  }
}

function loginRequest(username: string, suppliedPassword: string): Request {
  return new Request('https://ruleup.local/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password: suppliedPassword }),
  });
}

async function insertLegacyUser(username: string): Promise<void> {
  const { hashPassword } = await import('../src/auth/credentials');
  const now = new Date().toISOString();
  await testEnv.DB.prepare('DELETE FROM users WHERE id = ? OR username = ?')
    .bind(userId, username)
    .run();
  await testEnv.DB.prepare(
    `INSERT INTO users(id, username, password_hash, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).bind(userId, username, await hashPassword(password), now, now).run();
}

async function migrationTimestamp(username: string): Promise<string | null> {
  const row = await testEnv.DB.prepare(
    'SELECT auth_migrated_at FROM users WHERE username = ?',
  ).bind(username).first<{ auth_migrated_at: string | null }>();
  return row?.auth_migrated_at ?? null;
}
