import { authenticate } from '../auth/sessions';
import type { Env } from '../env';
import { errorResponse, jsonResponse } from '../http';
import {
  entityContracts,
  type EntityContract,
  type FieldContract,
} from './contracts';

type SyncOperation = 'create' | 'update' | 'upsert' | 'archive' | 'delete';

interface SyncRequestBody {
  operation: SyncOperation;
  data: Record<string, unknown>;
}

interface ExistingRow {
  user_id: string;
  updated_at: string;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const operations = new Set<SyncOperation>([
  'create',
  'update',
  'upsert',
  'archive',
  'delete',
]);

export async function handleSync(
  request: Request,
  env: Env,
  entityType: string,
): Promise<Response> {
  const contract = entityContracts[entityType];
  if (!contract) {
    return errorResponse('unsupported_entity', 'Unsupported sync entity type.', 404);
  }

  const user = await authenticate(request, env);
  if (!user) {
    return errorResponse('unauthorized', 'A valid session is required.', 401);
  }

  let decoded: unknown;
  try {
    decoded = await request.json();
  } catch {
    return errorResponse('invalid_json', 'Request body must be valid JSON.', 400);
  }
  if (!isSyncRequestBody(decoded)) {
    return errorResponse(
      'invalid_request',
      'A valid operation and data object are required.',
      400,
    );
  }
  if ('userId' in decoded.data || 'user_id' in decoded.data) {
    return errorResponse(
      'invalid_request',
      'user_id must not be supplied by the client.',
      400,
    );
  }

  const id = decoded.data.id;
  if (typeof id !== 'string' || !uuidPattern.test(id)) {
    return errorResponse('invalid_id', 'A valid UUID entity id is required.', 400);
  }
  if (decoded.operation === 'delete') {
    return deleteEntity(env, contract, entityType, user.id, id);
  }
  if (decoded.operation === 'archive' && !contract.archivable) {
    return errorResponse(
      'invalid_operation',
      'This entity cannot be archived.',
      400,
    );
  }

  const normalized = normalizeEntityData(contract, decoded.data);
  if (normalized instanceof Response) return normalized;

  const validationError = contract.validate?.(normalized);
  if (validationError) {
    return errorResponse('validation_error', validationError, 400);
  }
  if (decoded.operation === 'archive' && normalized.archivedAt === null) {
    return errorResponse(
      'validation_error',
      'archivedAt is required for archive operations.',
      400,
    );
  }

  const existing = await env.DB.prepare(
    `SELECT user_id, updated_at FROM ${contract.table} WHERE id = ?`,
  )
    .bind(id)
    .first<ExistingRow>();
  if (existing && existing.user_id !== user.id) {
    return errorResponse(
      'ownership_conflict',
      'The entity belongs to another user.',
      403,
    );
  }

  const incomingUpdatedAt = normalized.updatedAt as string;
  if (existing && incomingUpdatedAt <= existing.updated_at) {
    return syncResult(entityType, id, 'server_authoritative');
  }

  const relationError = await validateRelations(
    env,
    contract,
    user.id,
    normalized,
  );
  if (relationError) return relationError;

  try {
    await upsertEntity(env, contract, user.id, normalized);
  } catch (error) {
    return databaseConflict(error);
  }
  return syncResult(entityType, id, existing ? 'updated' : 'created');
}

function isSyncRequestBody(value: unknown): value is SyncRequestBody {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return (
    typeof body.operation === 'string' &&
    operations.has(body.operation as SyncOperation) &&
    !!body.data &&
    typeof body.data === 'object' &&
    !Array.isArray(body.data)
  );
}

function normalizeEntityData(
  contract: EntityContract,
  data: Record<string, unknown>,
): Record<string, unknown> | Response {
  const allowed = new Set(Object.keys(contract.fields));
  const unexpected = Object.keys(data).find((key) => !allowed.has(key));
  if (unexpected) {
    return errorResponse('invalid_field', `Unexpected field: ${unexpected}.`, 400);
  }

  const normalized: Record<string, unknown> = {};
  for (const [name, field] of Object.entries(contract.fields)) {
    if (!(name in data)) {
      return errorResponse('missing_field', `Missing required field: ${name}.`, 400);
    }
    const value = normalizeField(
      name,
      data[name],
      field,
      name === 'id' ||
          !!contract.relations?.some((relation) => relation.field === name),
    );
    if (value instanceof Response) return value;
    normalized[name] = value;
  }
  return normalized;
}

function normalizeField(
  name: string,
  value: unknown,
  field: FieldContract,
  mustBeUuid: boolean,
): unknown | Response {
  if (value === null && field.nullable) return null;
  if (field.type === 'string') {
    if (typeof value !== 'string') return invalidField(name);
    if (mustBeUuid && !uuidPattern.test(value)) {
      return errorResponse('invalid_id', `${name} must be a valid UUID.`, 400);
    }
    if (field.values && !field.values.includes(value)) return invalidField(name);
    return value;
  }
  if (field.type === 'number' || field.type === 'integer') {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return invalidField(name);
    }
    if (field.type === 'integer' && !Number.isInteger(value)) {
      return invalidField(name);
    }
    return value;
  }
  if (field.type === 'boolean') {
    return typeof value === 'boolean' ? Number(value) : invalidField(name);
  }
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) {
    return invalidField(name);
  }
  return new Date(value).toISOString();
}

function invalidField(name: string): Response {
  return errorResponse('invalid_field', `Invalid value for ${name}.`, 400);
}

async function validateRelations(
  env: Env,
  contract: EntityContract,
  userId: string,
  data: Record<string, unknown>,
): Promise<Response | null> {
  for (const relation of contract.relations ?? []) {
    const value = data[relation.field];
    if (value === null && contract.fields[relation.field]?.nullable) continue;
    const sameHabit =
      contract.table === 'check_ins' && relation.field !== 'habitId';
    const parent = await env.DB.prepare(
      `SELECT id FROM ${relation.table} WHERE id = ? AND user_id = ?${sameHabit ? ' AND habit_id = ?' : ''}`,
    )
      .bind(...(sameHabit ? [value, userId, data.habitId] : [value, userId]))
      .first();
    if (!parent) {
      return errorResponse(
        'invalid_relation',
        `${relation.field} does not reference an entity owned by the authenticated user.`,
        409,
      );
    }
  }
  if (contract.table === 'point_ledger' && data.sourceType === 'check_in') {
    const checkIn = await env.DB.prepare(
      'SELECT id FROM check_ins WHERE id = ? AND user_id = ?',
    )
      .bind(data.sourceId, userId)
      .first();
    if (!checkIn) {
      return errorResponse(
        'invalid_relation',
        'sourceId does not reference a check-in owned by the authenticated user.',
        409,
      );
    }
  }
  if (contract.table === 'habit_pauses') {
    const overlap = await env.DB.prepare(
      `SELECT id FROM habit_pauses
       WHERE user_id = ? AND habit_id = ? AND id <> ?
         AND start_date <= ? AND end_date >= ?
       LIMIT 1`,
    )
      .bind(
        userId,
        data.habitId,
        data.id,
        data.endDate,
        data.startDate,
      )
      .first();
    if (overlap) {
      return errorResponse(
        'pause_overlap',
        'The pause overlaps an existing pause for this habit.',
        409,
      );
    }
  }
  return null;
}

async function upsertEntity(
  env: Env,
  contract: EntityContract,
  userId: string,
  data: Record<string, unknown>,
): Promise<void> {
  const entries = Object.entries(contract.fields);
  const columns = ['user_id', ...entries.map(([, field]) => field.column)];
  const values = [userId, ...entries.map(([name]) => data[name])];
  const placeholders = values.map(() => '?');
  const updates = entries
    .filter(([, field]) => field.column !== 'id')
    .map(([, field]) => `${field.column} = excluded.${field.column}`);
  const sql = `INSERT INTO ${contract.table} (${columns.join(', ')}) VALUES (${placeholders.join(', ')}) ON CONFLICT(id) DO UPDATE SET ${updates.join(', ')}`;
  await env.DB.prepare(sql).bind(...values).run();
}

async function deleteEntity(
  env: Env,
  contract: EntityContract,
  entityType: string,
  userId: string,
  id: string,
): Promise<Response> {
  if (!contract.deletable) {
    return errorResponse(
      'invalid_operation',
      'This entity must be archived instead of deleted.',
      400,
    );
  }
  const existing = await env.DB.prepare(
    `SELECT user_id FROM ${contract.table} WHERE id = ?`,
  )
    .bind(id)
    .first<{ user_id: string }>();
  if (existing && existing.user_id !== userId) {
    return errorResponse(
      'ownership_conflict',
      'The entity belongs to another user.',
      403,
    );
  }
  if (existing) {
    await env.DB.prepare(
      `DELETE FROM ${contract.table} WHERE id = ? AND user_id = ?`,
    )
      .bind(id, userId)
      .run();
  }
  return syncResult(entityType, id, existing ? 'deleted' : 'unchanged');
}

function databaseConflict(error: unknown): Response {
  const detail = String(error).slice(0, 300);
  if (detail.includes('point_ledger.user_id') && detail.includes('source_id')) {
    return errorResponse(
      'duplicate_source',
      'A ledger entry already exists for this source.',
      409,
    );
  }
  if (detail.includes('FOREIGN KEY')) {
    return errorResponse(
      'invalid_relation',
      'A referenced entity is missing or not owned by the user.',
      409,
    );
  }
  return errorResponse(
    'sync_conflict',
    'The entity conflicts with existing server data.',
    409,
  );
}

function syncResult(entityType: string, entityId: string, status: string) {
  return jsonResponse({ data: { entityType, entityId, status } });
}
