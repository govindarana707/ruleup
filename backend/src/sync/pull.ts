import { authenticate } from '../auth/sessions';
import type { Env } from '../env';
import { errorResponse, jsonResponse } from '../http';
import { entityContracts, type EntityContract } from './contracts';

interface ChangeRow {
  sequence: number;
  entity_type: string;
  entity_id: string;
  operation: 'upsert' | 'archive' | 'delete';
  updated_at: string;
}

const pageSize = 200;

export async function handlePull(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  if (!user) {
    return errorResponse('unauthorized', 'A valid session is required.', 401);
  }

  const cursorValue = new URL(request.url).searchParams.get('cursor') ?? '0';
  if (!/^\d+$/.test(cursorValue)) {
    return errorResponse('invalid_cursor', 'Cursor must be a non-negative integer.', 400);
  }
  const cursor = Number(cursorValue);
  if (!Number.isSafeInteger(cursor)) {
    return errorResponse('invalid_cursor', 'Cursor is outside the supported range.', 400);
  }

  const result = await env.DB.prepare(
    `SELECT sequence, entity_type, entity_id, operation, updated_at
     FROM sync_changes
     WHERE user_id = ? AND sequence > ?
     ORDER BY sequence ASC
     LIMIT ?`,
  )
    .bind(user.id, cursor, pageSize + 1)
    .all<ChangeRow>();
  const rows = result.results;
  const hasMore = rows.length > pageSize;
  const page = rows.slice(0, pageSize);
  const changes = [];

  for (const change of page) {
    if (change.operation === 'delete') {
      changes.push({
        cursor: String(change.sequence),
        entityType: change.entity_type,
        operation: 'delete',
        updatedAt: change.updated_at,
        data: { id: change.entity_id },
      });
      continue;
    }

    const contract = entityContracts[change.entity_type];
    if (!contract) continue;
    const row = await env.DB.prepare(
      `SELECT * FROM ${contract.table} WHERE id = ? AND user_id = ?`,
    )
      .bind(change.entity_id, user.id)
      .first<Record<string, unknown>>();
    changes.push({
      cursor: String(change.sequence),
      entityType: change.entity_type,
      operation: row ? change.operation : 'delete',
      updatedAt: change.updated_at,
      data: row ? serializeRow(contract, row) : { id: change.entity_id },
    });
  }

  return jsonResponse({
    data: {
      changes,
      nextCursor: page.length
        ? String(page[page.length - 1].sequence)
        : cursorValue,
      hasMore,
    },
  });
}

function serializeRow(
  contract: EntityContract,
  row: Record<string, unknown>,
): Record<string, unknown> {
  const data: Record<string, unknown> = {};
  for (const [name, field] of Object.entries(contract.fields)) {
    const value = row[field.column];
    data[name] = field.type === 'boolean' ? value === 1 : value;
  }
  return data;
}
