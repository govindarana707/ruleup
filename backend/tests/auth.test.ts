import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { testEnv } from './setup';

const validPassword = 'correct-horse-battery-staple';

interface AuthResponse {
  data: {
    user: {
      id: string;
      username: string;
      createdAt: string;
      updatedAt: string;
    };
    token: string;
    expiresAt: string;
  };
}

async function post(
  path: string,
  body: unknown,
  token?: string,
): Promise<Response> {
  return SELF.fetch(`https://ruleup.local${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

async function signup(username: string): Promise<AuthResponse> {
  const response = await post('/auth/signup', {
    username,
    password: validPassword,
  });
  expect(response.status).toBe(201);
  return response.json<AuthResponse>();
}

describe('authentication', () => {
  it('signs up a user with a normalized username', async () => {
    const response = await post('/auth/signup', {
      username: '  New_User  ',
      password: validPassword,
    });
    const body = await response.json<AuthResponse>();

    expect(response.status).toBe(201);
    expect(body.data.user.username).toBe('new_user');
    expect(body.data.user.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(body.data.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(JSON.stringify(body)).not.toContain(validPassword);
    expect(JSON.stringify(body)).not.toContain('SUPABASE_SERVICE_ROLE_KEY');
  });

  it('rejects a duplicate normalized username', async () => {
    await signup('Duplicate_User');
    const response = await post('/auth/signup', {
      username: ' duplicate_user ',
      password: validPassword,
    });

    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: 'username_taken' },
    });
  });

  it('stores a salted password hash instead of the password', async () => {
    const signupBody = await signup('hashed_user');
    const stored = await testEnv.DB.prepare(
      `SELECT users.password_hash, sessions.token_hash
       FROM users
       INNER JOIN sessions ON sessions.user_id = users.id
       WHERE users.username = ?`,
    )
      .bind('hashed_user')
      .first<{ password_hash: string; token_hash: string }>();

    expect(stored?.password_hash).not.toBe(validPassword);
    expect(stored?.password_hash).toMatch(
      /^pbkdf2_sha256\$600000\$[A-Za-z0-9_-]+\$[A-Za-z0-9_-]+$/,
    );
    expect(stored?.token_hash).not.toBe(signupBody.data.token);
    expect(stored?.token_hash).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it('logs in with valid normalized credentials', async () => {
    const signupBody = await signup('login_user');
    const response = await post('/auth/login', {
      username: ' LOGIN_USER ',
      password: validPassword,
    });
    const body = await response.json<AuthResponse>();

    expect(response.status).toBe(200);
    expect(body.data.user.id).toBe(signupBody.data.user.id);
    expect(body.data.token).not.toBe(signupBody.data.token);
  });

  it('rejects an invalid login', async () => {
    await signup('invalid_login_user');
    const response = await post('/auth/login', {
      username: 'invalid_login_user',
      password: 'this-password-is-wrong',
    });

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: 'invalid_credentials' },
    });
  });

  it('returns the authenticated user from the session', async () => {
    const signupBody = await signup('current_user');
    const response = await SELF.fetch('https://ruleup.local/auth/me', {
      headers: { authorization: `Bearer ${signupBody.data.token}` },
    });
    const body = (await response.json()) as {
      data: { user: AuthResponse['data']['user'] };
    };

    expect(response.status).toBe(200);
    expect(body.data.user).toEqual(signupBody.data.user);
  });

  it('rejects an unauthenticated current-user request', async () => {
    const response = await SELF.fetch('https://ruleup.local/auth/me');

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: 'unauthorized' },
    });
  });

  it('revokes the session on logout', async () => {
    const signupBody = await signup('logout_user');
    const authorization = `Bearer ${signupBody.data.token}`;
    const logout = await post('/auth/logout', {}, signupBody.data.token);
    const me = await SELF.fetch('https://ruleup.local/auth/me', {
      headers: { authorization },
    });

    expect(logout.status).toBe(200);
    await expect(logout.json()).resolves.toEqual({
      data: { success: true },
    });
    expect(me.status).toBe(401);
  });
});
