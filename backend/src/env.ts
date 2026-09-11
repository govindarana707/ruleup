export interface Env {
  DB: D1Database;
  REWARD_IMAGES: R2Bucket;
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
}
