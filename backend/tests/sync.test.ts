import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { testEnv } from './setup';

const password = 'correct-horse-battery-staple';

async function signup(username: string) {
  const response = await SELF.fetch('https://ruleup.local/auth/signup', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  expect(response.status).toBe(201);
  return response.json<{
    data: { user: { id: string }; token: string };
  }>();
}

async function sync(
  token: string,
  entityType: string,
  operation: string,
  data: Record<string, unknown>,
) {
  return SELF.fetch(`https://ruleup.local/sync/${entityType}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ operation, data }),
  });
}

async function pull(token: string, cursor = '0') {
  return SELF.fetch(`https://ruleup.local/sync/pull?cursor=${cursor}`, {
    headers: { authorization: `Bearer ${token}` },
  });
}

function category(
  id: string,
  updatedAt = '2026-01-01T00:00:00.000Z',
  name = 'Health',
) {
  return {
    id,
    name,
    sortOrder: 0,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt,
    archivedAt: null,
  };
}

function habit(id: string, categoryId: string | null) {
  return {
    id,
    categoryId,
    name: 'Walk',
    measurementType: 'yes_no',
    sortOrder: 0,
    missedPenaltyEnabled: false,
    missedPenaltyPoints: 0,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    archivedAt: null,
  };
}

describe('authenticated entity sync', () => {
  it('requires authentication and rejects client-supplied user identity', async () => {
    const id = crypto.randomUUID();
    const unauthorized = await SELF.fetch(
      'https://ruleup.local/sync/category',
      {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ operation: 'create', data: category(id) }),
      },
    );
    expect(unauthorized.status).toBe(401);

    const account = await signup('sync_identity');
    const spoofed = await sync(account.data.token, 'category', 'create', {
      ...category(id),
      userId: crypto.randomUUID(),
    });
    expect(spoofed.status).toBe(400);
  });

  it('upserts idempotently and keeps the latest valid server version', async () => {
    const account = await signup('sync_updates');
    const id = crypto.randomUUID();

    const created = await sync(
      account.data.token,
      'category',
      'create',
      category(id),
    );
    expect(created.status).toBe(200);

    const repeated = await sync(
      account.data.token,
      'category',
      'create',
      category(id),
    );
    await expect(repeated.json()).resolves.toMatchObject({
      data: { status: 'server_authoritative' },
    });

    await sync(
      account.data.token,
      'category',
      'update',
      category(id, '2026-01-02T00:00:00.000Z', 'Movement'),
    );
    const stale = await sync(
      account.data.token,
      'category',
      'update',
      category(id, '2026-01-01T12:00:00.000Z', 'Stale'),
    );
    await expect(stale.json()).resolves.toMatchObject({
      data: { status: 'server_authoritative' },
    });

    const archivedAt = '2026-01-03T00:00:00.000Z';
    const archived = await sync(account.data.token, 'category', 'archive', {
      ...category(id, archivedAt, 'Movement'),
      archivedAt,
    });
    expect(archived.status).toBe(200);

    const row = await testEnv.DB.prepare(
      'SELECT user_id, name, archived_at FROM categories WHERE id = ?',
    )
      .bind(id)
      .first<{ user_id: string; name: string; archived_at: string }>();
    expect(row).toEqual({
      user_id: account.data.user.id,
      name: 'Movement',
      archived_at: archivedAt,
    });
  });

  it('validates relationship ownership using the authenticated user', async () => {
    const owner = await signup('sync_owner');
    const other = await signup('sync_other');
    const categoryId = crypto.randomUUID();
    await sync(owner.data.token, 'category', 'create', category(categoryId));

    const response = await sync(other.data.token, 'habit', 'create', habit(
      crypto.randomUUID(),
      categoryId,
    ));
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({
      error: { code: 'invalid_relation' },
    });
  });

  it('preserves check-in snapshots and prevents duplicate ledger sources', async () => {
    const account = await signup('sync_snapshots');
    const habitId = crypto.randomUUID();
    await sync(account.data.token, 'habit', 'create', habit(habitId, null));

    const checkInId = crypto.randomUUID();
    const checkIn = await sync(account.data.token, 'check_in', 'create', {
      id: checkInId,
      habitId,
      habitDate: '2026-01-02',
      optionId: null,
      measuredValue: 1,
      note: 'snapshot',
      awardedPoints: 7,
      matchedRuleId: null,
      checkedInAt: '2026-01-02T08:00:00.000Z',
      editableUntil: '2026-01-03T12:00:00.000Z',
      createdAt: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-02T08:00:00.000Z',
    });
    expect(checkIn.status).toBe(200);

    const ledger = {
      sourceType: 'check_in',
      sourceId: checkInId,
      points: 7,
      reason: null,
      createdAt: '2026-01-02T08:00:00.000Z',
      updatedAt: '2026-01-02T08:00:00.000Z',
    };
    expect(
      (await sync(account.data.token, 'point_ledger', 'create', {
        id: crypto.randomUUID(),
        ...ledger,
      })).status,
    ).toBe(200);
    const duplicate = await sync(
      account.data.token,
      'point_ledger',
      'create',
      { id: crypto.randomUUID(), ...ledger },
    );
    expect(duplicate.status).toBe(409);
    await expect(duplicate.json()).resolves.toMatchObject({
      error: { code: 'duplicate_source' },
    });

    const missedSource = `${habitId}:2026-01-01`;
    const missed = await sync(
      account.data.token,
      'point_ledger',
      'create',
      {
        id: crypto.randomUUID(),
        sourceType: 'missed_check_in',
        sourceId: missedSource,
        points: -2,
        reason: 'Missed check-in snapshot',
        createdAt: '2026-01-03T08:00:00.000Z',
        updatedAt: '2026-01-03T08:00:00.000Z',
      },
    );
    expect(missed.status).toBe(200);

    const stored = await testEnv.DB.prepare(
      'SELECT awarded_points, matched_rule_id FROM check_ins WHERE id = ?',
    )
      .bind(checkInId)
      .first();
    expect(stored).toEqual({ awarded_points: 7, matched_rule_id: null });
  });

  it('deletes ephemeral entities idempotently', async () => {
    const account = await signup('sync_delete');
    const habitId = crypto.randomUUID();
    await sync(account.data.token, 'habit', 'create', habit(habitId, null));
    const scheduleId = crypto.randomUUID();
    const schedule = {
      id: scheduleId,
      habitId,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    };
    expect(
      (await sync(account.data.token, 'habit_schedule', 'create', schedule))
        .status,
    ).toBe(200);
    const removed = await sync(account.data.token, 'habit_schedule', 'delete', {
      id: scheduleId,
    });
    const repeated = await sync(account.data.token, 'habit_schedule', 'delete', {
      id: scheduleId,
    });
    await expect(removed.json()).resolves.toMatchObject({
      data: { status: 'deleted' },
    });
    await expect(repeated.json()).resolves.toMatchObject({
      data: { status: 'unchanged' },
    });
  });

  it('supports initial and incremental server-authoritative pulls', async () => {
    const account = await signup('pull_incremental');
    const id = crypto.randomUUID();
    await sync(account.data.token, 'category', 'create', category(id));

    const initial = await pull(account.data.token);
    const initialBody = await initial.json<{
      data: {
        changes: Array<{
          cursor: string;
          entityType: string;
          operation: string;
          data: Record<string, unknown>;
        }>;
        nextCursor: string;
        hasMore: boolean;
      };
    }>();
    expect(initial.status).toBe(200);
    expect(initialBody.data.changes).toHaveLength(1);
    expect(initialBody.data.changes[0]).toMatchObject({
      entityType: 'category',
      operation: 'upsert',
      data: { id, name: 'Health' },
    });
    expect(initialBody.data.changes[0].data).not.toHaveProperty('userId');

    const unchanged = await pull(
      account.data.token,
      initialBody.data.nextCursor,
    );
    await expect(unchanged.json()).resolves.toMatchObject({
      data: { changes: [], nextCursor: initialBody.data.nextCursor },
    });

    await sync(
      account.data.token,
      'category',
      'update',
      category(id, '2026-01-02T00:00:00.000Z', 'Updated'),
    );
    const incremental = await pull(
      account.data.token,
      initialBody.data.nextCursor,
    );
    const incrementalBody = await incremental.json<{
      data: {
        changes: Array<{ data: { name: string } }>;
        nextCursor: string;
      };
    }>();
    expect(incrementalBody.data.changes).toHaveLength(1);
    expect(incrementalBody.data.changes[0].data.name).toBe('Updated');

    await sync(
      account.data.token,
      'category',
      'update',
      category(id, '2026-01-01T12:00:00.000Z', 'Stale'),
    );
    const afterStale = await pull(
      account.data.token,
      incrementalBody.data.nextCursor,
    );
    await expect(afterStale.json()).resolves.toMatchObject({
      data: { changes: [] },
    });
  });

  it('pulls deletions repeatedly without crossing user boundaries', async () => {
    const owner = await signup('pull_delete_owner');
    const other = await signup('pull_delete_other');
    const habitId = crypto.randomUUID();
    await sync(owner.data.token, 'habit', 'create', habit(habitId, null));
    const scheduleId = crypto.randomUUID();
    await sync(owner.data.token, 'habit_schedule', 'create', {
      id: scheduleId,
      habitId,
      scheduleType: 'daily',
      scheduleConfig: '{}',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    });
    const beforeDelete = await pull(owner.data.token);
    const beforeBody = await beforeDelete.json<{
      data: { nextCursor: string };
    }>();
    await sync(owner.data.token, 'habit_schedule', 'delete', {
      id: scheduleId,
    });

    const first = await pull(owner.data.token, beforeBody.data.nextCursor);
    const repeated = await pull(owner.data.token, beforeBody.data.nextCursor);
    const expected = {
      data: {
        changes: [
          {
            entityType: 'habit_schedule',
            operation: 'delete',
            data: { id: scheduleId },
          },
        ],
      },
    };
    await expect(first.json()).resolves.toMatchObject(expected);
    await expect(repeated.json()).resolves.toMatchObject(expected);

    const isolated = await pull(other.data.token);
    await expect(isolated.json()).resolves.toMatchObject({
      data: { changes: [] },
    });
  });
});
