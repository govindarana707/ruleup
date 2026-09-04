import {
  applyD1Migrations,
  env,
  type D1Migration,
} from 'cloudflare:test';
import { beforeEach } from 'vitest';
import type { Env } from '../src/env';

interface TestEnv extends Env {
  TEST_MIGRATIONS: D1Migration[];
}

export const testEnv = env as TestEnv;

beforeEach(async () => {
  await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
});
