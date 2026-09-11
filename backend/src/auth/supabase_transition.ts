import type {
  LegacyIdentity,
  SupabaseAuthAdmin,
  SupabaseSessionPayload,
} from '../supabase/admin';

export interface AuthMigrationUser extends LegacyIdentity {
  authMigratedAt: string | null;
}

export interface AuthTransitionResult {
  session: SupabaseSessionPayload | null;
  migratedAt: string | null;
}

export async function transitionSupabaseAuth(
  admin: SupabaseAuthAdmin,
  user: AuthMigrationUser,
  password: string,
  now: () => Date = () => new Date(),
): Promise<AuthTransitionResult> {
  if (!user.authMigratedAt) {
    await admin.ensureLegacyIdentity(user, password);
  }
  const session = await admin.signIn(user, password);
  return {
    session,
    migratedAt: user.authMigratedAt ?? now().toISOString(),
  };
}
