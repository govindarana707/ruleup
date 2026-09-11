import type { Env } from '../env';

const uuidV4Pattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface SupabaseSessionPayload {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  userId: string;
}

export interface LegacyIdentity {
  id: string;
  username: string;
}

export interface SupabaseAuthAdmin {
  ensureLegacyIdentity(
    identity: LegacyIdentity,
    password: string,
  ): Promise<void>;
  signIn(identity: LegacyIdentity, password: string): Promise<SupabaseSessionPayload>;
}

interface SupabaseUserResponse {
  id?: unknown;
  email?: unknown;
  user_metadata?: unknown;
  app_metadata?: unknown;
}

interface SupabaseTokenResponse {
  access_token?: unknown;
  refresh_token?: unknown;
  expires_at?: unknown;
  expires_in?: unknown;
  user?: SupabaseUserResponse;
}

export class SupabaseAdminError extends Error {
  constructor(
    readonly kind:
      | 'configuration'
      | 'invalid_credentials'
      | 'identity_conflict'
      | 'network'
      | 'supabase_failure',
    message: string,
  ) {
    super(message);
    this.name = 'SupabaseAdminError';
  }
}

export function createSupabaseAuthAdmin(
  env: Env,
  fetcher: typeof fetch = fetch,
): SupabaseAuthAdmin | null {
  const url = env.SUPABASE_URL?.trim() ?? '';
  const serviceRoleKey = env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? '';
  if (!url && !serviceRoleKey) return null;
  if (!url || !serviceRoleKey) {
    throw new SupabaseAdminError(
      'configuration',
      'Supabase admin configuration is incomplete.',
    );
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new SupabaseAdminError('configuration', 'SUPABASE_URL is invalid.');
  }
  if (parsed.protocol !== 'https:' && parsed.hostname !== 'localhost') {
    throw new SupabaseAdminError(
      'configuration',
      'SUPABASE_URL must use HTTPS outside localhost.',
    );
  }
  return new HttpSupabaseAuthAdmin(parsed, serviceRoleKey, fetcher);
}

export function syntheticAuthEmail(userId: string): string {
  if (!uuidV4Pattern.test(userId)) {
    throw new SupabaseAdminError(
      'identity_conflict',
      'Legacy identity must be a UUIDv4.',
    );
  }
  return `${userId.toLowerCase()}@auth.ruleup.invalid`;
}

export class HttpSupabaseAuthAdmin implements SupabaseAuthAdmin {
  constructor(
    private readonly baseUrl: URL,
    private readonly serviceRoleKey: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {}

  async ensureLegacyIdentity(
    identity: LegacyIdentity,
    password: string,
  ): Promise<void> {
    const email = syntheticAuthEmail(identity.id);
    const attributes = {
      id: identity.id,
      email,
      password,
      email_confirm: true,
      user_metadata: { username: identity.username },
      app_metadata: {
        identity_source: 'ruleup_legacy',
        legacy_user_id: identity.id,
      },
    };
    const create = await this.request('/auth/v1/admin/users', {
      method: 'POST',
      body: JSON.stringify(attributes),
    });

    if (create.ok) {
      this.verifyIdentity(await readJson<SupabaseUserResponse>(create), identity);
    } else if (create.status === 409 || create.status === 422) {
      const existing = await this.request(`/auth/v1/admin/users/${identity.id}`);
      if (!existing.ok) throw supabaseFailure('Unable to verify existing Supabase identity.');
      this.verifyIdentity(await readJson<SupabaseUserResponse>(existing), identity);
      const update = await this.request(`/auth/v1/admin/users/${identity.id}`, {
        method: 'PUT',
        body: JSON.stringify({
          password,
          user_metadata: attributes.user_metadata,
          app_metadata: attributes.app_metadata,
        }),
      });
      if (!update.ok) throw supabaseFailure('Unable to reconcile Supabase identity.');
    } else {
      throw supabaseFailure('Unable to create Supabase identity.');
    }

    const profile = await this.request('/rest/v1/profiles?on_conflict=id', {
      method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify({ id: identity.id, username: identity.username }),
    });
    if (!profile.ok) throw supabaseFailure('Unable to synchronize Supabase profile.');
  }

  async signIn(
    identity: LegacyIdentity,
    password: string,
  ): Promise<SupabaseSessionPayload> {
    const response = await this.request('/auth/v1/token?grant_type=password', {
      method: 'POST',
      body: JSON.stringify({
        email: syntheticAuthEmail(identity.id),
        password,
      }),
    });
    if (response.status === 400 || response.status === 401) {
      throw new SupabaseAdminError(
        'invalid_credentials',
        'Supabase rejected the credentials.',
      );
    }
    if (!response.ok) throw supabaseFailure('Supabase sign-in failed.');
    const body = await readJson<SupabaseTokenResponse>(response);
    const userId = body.user?.id;
    const accessToken = body.access_token;
    const refreshToken = body.refresh_token;
    const expiresAt =
      typeof body.expires_at === 'number'
        ? body.expires_at
        : Math.floor(Date.now() / 1000) + Number(body.expires_in);
    if (
      userId !== identity.id ||
      typeof accessToken !== 'string' ||
      typeof refreshToken !== 'string' ||
      !Number.isSafeInteger(expiresAt)
    ) {
      throw new SupabaseAdminError(
        'identity_conflict',
        'Supabase session identity does not match the legacy user.',
      );
    }
    return { accessToken, refreshToken, expiresAt, userId };
  }

  private verifyIdentity(
    user: SupabaseUserResponse,
    identity: LegacyIdentity,
  ): void {
    const metadata = isRecord(user.app_metadata) ? user.app_metadata : {};
    if (
      user.id !== identity.id ||
      user.email !== syntheticAuthEmail(identity.id) ||
      metadata.legacy_user_id !== identity.id ||
      metadata.identity_source !== 'ruleup_legacy'
    ) {
      throw new SupabaseAdminError(
        'identity_conflict',
        'An unrelated Supabase identity already occupies the legacy UUID.',
      );
    }
  }

  private async request(path: string, init: RequestInit = {}): Promise<Response> {
    try {
      return await this.fetcher(new URL(path, this.baseUrl), {
        ...init,
        headers: {
          apikey: this.serviceRoleKey,
          authorization: `Bearer ${this.serviceRoleKey}`,
          'content-type': 'application/json',
          ...init.headers,
        },
      });
    } catch {
      throw new SupabaseAdminError('network', 'Unable to reach Supabase Auth.');
    }
  }
}

async function readJson<T>(response: Response): Promise<T> {
  try {
    return (await response.json()) as T;
  } catch {
    throw supabaseFailure('Supabase returned an invalid response.');
  }
}

function supabaseFailure(message: string): SupabaseAdminError {
  return new SupabaseAdminError('supabase_failure', message);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
