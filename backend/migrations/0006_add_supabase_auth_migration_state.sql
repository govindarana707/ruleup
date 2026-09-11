ALTER TABLE users ADD COLUMN auth_migrated_at TEXT;
ALTER TABLE users ADD COLUMN supabase_auth_email TEXT;

CREATE UNIQUE INDEX users_supabase_auth_email_idx
  ON users(supabase_auth_email)
  WHERE supabase_auth_email IS NOT NULL;
