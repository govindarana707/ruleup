import type { Env } from '../env';
import { errorResponse, jsonResponse } from '../http';
import {
  hashPassword,
  validateCredentials,
  verifyPassword,
} from './credentials';
import {
  authenticate,
  createSession,
  revokeSession,
  type AuthenticatedUser,
} from './sessions';
import { transitionSupabaseAuth } from './supabase_transition';
import {
  createSupabaseAuthAdmin,
  SupabaseAdminError,
  syntheticAuthEmail,
  type SupabaseAuthAdmin,
  type SupabaseSessionPayload,
} from '../supabase/admin';

interface UserRow {
  id: string;
  username: string;
  password_hash: string;
  created_at: string;
  updated_at: string;
  auth_migrated_at: string | null;
  supabase_auth_email: string | null;
}

export async function handleSignup(
  request: Request,
  env: Env,
): Promise<Response> {
  const credentials = validateCredentials(await readJson(request));
  if (!credentials) {
    return invalidCredentialsInput();
  }

  const existingUser = await env.DB.prepare(
    'SELECT id FROM users WHERE username = ? LIMIT 1',
  )
    .bind(credentials.username)
    .first();
  if (existingUser) {
    return usernameTaken();
  }

  const userId = crypto.randomUUID();
  const now = new Date().toISOString();
  const passwordHash = await hashPassword(credentials.password);
  const session = await createSession();

  try {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO users
           (id, username, password_hash, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?)`,
      ).bind(userId, credentials.username, passwordHash, now, now),
      env.DB.prepare(
        `INSERT INTO sessions
           (id, user_id, token_hash, expires_at, created_at)
         VALUES (?, ?, ?, ?, ?)`,
      ).bind(
        session.id,
        userId,
        session.tokenHash,
        session.expiresAt,
        session.createdAt,
      ),
    ]);
  } catch (error) {
    if (isDuplicateUsernameError(error)) {
      return usernameTaken();
    }
    throw error;
  }

  return jsonResponse(
    {
      data: {
        user: toPublicUser({
          id: userId,
          username: credentials.username,
          password_hash: passwordHash,
          created_at: now,
          updated_at: now,
          auth_migrated_at: null,
          supabase_auth_email: null,
        }),
        token: session.token,
        expiresAt: session.expiresAt,
      },
    },
    201,
  );
}

export async function handleLogin(
  request: Request,
  env: Env,
  adminOverride?: SupabaseAuthAdmin | null,
): Promise<Response> {
  const credentials = validateCredentials(await readJson(request));
  if (!credentials) {
    return invalidCredentialsInput();
  }

  const user = await env.DB.prepare(
    `SELECT id, username, password_hash, created_at, updated_at,
            auth_migrated_at, supabase_auth_email
     FROM users
     WHERE username = ?
     LIMIT 1`,
  )
    .bind(credentials.username)
    .first<UserRow>();

  if (!user) {
    return errorResponse('invalid_credentials', 'Invalid username or password.', 401);
  }

  let supabaseSession: SupabaseSessionPayload | null = null;
  let migratedAt = user.auth_migrated_at;
  let legacyVerified = false;
  let admin: SupabaseAuthAdmin | null = adminOverride ?? null;
  if (adminOverride === undefined) {
    try {
      admin = createSupabaseAuthAdmin(env);
    } catch {
      // Incomplete optional configuration must never disable legacy login.
    }
  }

  if (admin && user.auth_migrated_at) {
    try {
      const transition = await transitionSupabaseAuth(
        admin,
        {
          id: user.id,
          username: user.username,
          authMigratedAt: user.auth_migrated_at,
        },
        credentials.password,
      );
      supabaseSession = transition.session;
    } catch (error) {
      if (error instanceof SupabaseAdminError && error.kind === 'invalid_credentials') {
        return errorResponse('invalid_credentials', 'Invalid username or password.', 401);
      }
      legacyVerified = await verifyPassword(
        credentials.password,
        user.password_hash,
      );
    }
  } else {
    legacyVerified = await verifyPassword(credentials.password, user.password_hash);
  }

  if (!supabaseSession && !legacyVerified) {
    return errorResponse('invalid_credentials', 'Invalid username or password.', 401);
  }

  if (admin && !user.auth_migrated_at && legacyVerified) {
    try {
      const transition = await transitionSupabaseAuth(
        admin,
        { id: user.id, username: user.username, authMigratedAt: null },
        credentials.password,
      );
      supabaseSession = transition.session;
      migratedAt = transition.migratedAt;
    } catch {
      // Lazy migration is best-effort. The verified legacy login remains valid.
    }
  }

  const session = await createSession();
  const statements = [
    env.DB.prepare(
      `INSERT INTO sessions
       (id, user_id, token_hash, expires_at, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).bind(
      session.id,
      user.id,
      session.tokenHash,
      session.expiresAt,
      session.createdAt,
    ),
  ];
  if (supabaseSession && migratedAt && !user.auth_migrated_at) {
    statements.push(
      env.DB.prepare(
        `UPDATE users
         SET auth_migrated_at = ?, supabase_auth_email = ?, updated_at = ?
         WHERE id = ? AND auth_migrated_at IS NULL`,
      ).bind(migratedAt, syntheticAuthEmail(user.id), migratedAt, user.id),
    );
  }
  await env.DB.batch(statements);

  return jsonResponse({
    data: {
      user: toPublicUser(user),
      token: session.token,
      expiresAt: session.expiresAt,
      ...(supabaseSession ? { supabaseSession } : {}),
    },
  });
}

export async function handleMe(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  return user
    ? jsonResponse({ data: { user } })
    : unauthorizedResponse();
}

export async function handleLogout(
  request: Request,
  env: Env,
): Promise<Response> {
  return (await revokeSession(request, env))
    ? jsonResponse({ data: { success: true } })
    : unauthorizedResponse();
}

function toPublicUser(user: UserRow): AuthenticatedUser {
  return {
    id: user.id,
    username: user.username,
    createdAt: user.created_at,
    updatedAt: user.updated_at,
  };
}

async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function invalidCredentialsInput(): Response {
  return errorResponse(
    'invalid_input',
    'Username must be 3–30 lowercase letters, numbers, or underscores after normalization; password must be 12–128 characters.',
    400,
  );
}

function usernameTaken(): Response {
  return errorResponse('username_taken', 'Username is already in use.', 409);
}

function unauthorizedResponse(): Response {
  return errorResponse('unauthorized', 'Authentication is required.', 401);
}

function isDuplicateUsernameError(error: unknown): boolean {
  return String(error).includes('UNIQUE constraint failed: users.username');
}
