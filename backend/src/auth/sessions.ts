import type { Env } from '../env';

const sessionLifetimeMilliseconds = 30 * 24 * 60 * 60 * 1000;
const tokenLength = 32;

const encoder = new TextEncoder();

export interface AuthenticatedUser {
  id: string;
  username: string;
  createdAt: string;
  updatedAt: string;
}

interface AuthenticatedUserRow {
  id: string;
  username: string;
  created_at: string;
  updated_at: string;
}

export interface NewSession {
  id: string;
  token: string;
  tokenHash: string;
  expiresAt: string;
  createdAt: string;
}

export async function createSession(): Promise<NewSession> {
  const tokenBytes = crypto.getRandomValues(new Uint8Array(tokenLength));
  const token = toBase64Url(tokenBytes);
  const now = new Date();

  return {
    id: crypto.randomUUID(),
    token,
    tokenHash: await hashToken(token),
    expiresAt: new Date(
      now.getTime() + sessionLifetimeMilliseconds,
    ).toISOString(),
    createdAt: now.toISOString(),
  };
}

export function readBearerToken(request: Request): string | null {
  const authorization = request.headers.get('authorization');
  const match = authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/);
  return match?.[1] ?? null;
}

export async function authenticate(
  request: Request,
  env: Env,
): Promise<AuthenticatedUser | null> {
  const token = readBearerToken(request);
  if (!token) {
    return null;
  }

  const row = await env.DB.prepare(
    `SELECT users.id, users.username, users.created_at, users.updated_at
     FROM sessions
     INNER JOIN users ON users.id = sessions.user_id
     WHERE sessions.token_hash = ?
       AND sessions.revoked_at IS NULL
       AND sessions.expires_at > ?
     LIMIT 1`,
  )
    .bind(await hashToken(token), new Date().toISOString())
    .first<AuthenticatedUserRow>();

  return row ? toAuthenticatedUser(row) : null;
}

export async function revokeSession(
  request: Request,
  env: Env,
): Promise<boolean> {
  const token = readBearerToken(request);
  if (!token) {
    return false;
  }

  const now = new Date().toISOString();
  const result = await env.DB.prepare(
    `UPDATE sessions
     SET revoked_at = ?
     WHERE token_hash = ?
       AND revoked_at IS NULL
       AND expires_at > ?`,
  )
    .bind(now, await hashToken(token), now)
    .run();

  return (result.meta.changes ?? 0) > 0;
}

function toAuthenticatedUser(row: AuthenticatedUserRow): AuthenticatedUser {
  return {
    id: row.id,
    username: row.username,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', encoder.encode(token));
  return toBase64Url(new Uint8Array(digest));
}

function toBase64Url(value: Uint8Array): string {
  let binary = '';
  for (const byte of value) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}
