CREATE TABLE sync_changes (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK(entity_type IN (
    'category',
    'habit',
    'habit_option',
    'habit_schedule',
    'point_rule',
    'check_in',
    'point_ledger',
    'habit_pause',
    'reward',
    'habit_reminder'
  )),
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK(operation IN ('upsert', 'archive', 'delete')),
  updated_at TEXT NOT NULL
);

CREATE INDEX sync_changes_user_sequence_idx
  ON sync_changes(user_id, sequence);

INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'category', id,
    CASE WHEN archived_at IS NULL THEN 'upsert' ELSE 'archive' END, updated_at
  FROM categories;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'habit', id,
    CASE WHEN archived_at IS NULL THEN 'upsert' ELSE 'archive' END, updated_at
  FROM habits;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'habit_option', id,
    CASE WHEN archived_at IS NULL THEN 'upsert' ELSE 'archive' END, updated_at
  FROM habit_options;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'habit_schedule', id, 'upsert', updated_at
  FROM habit_schedules;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'point_rule', id,
    CASE WHEN archived_at IS NULL THEN 'upsert' ELSE 'archive' END, updated_at
  FROM point_rules;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'check_in', id, 'upsert', updated_at
  FROM check_ins;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'point_ledger', id, 'upsert', updated_at
  FROM point_ledger;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'habit_pause', id, 'upsert', updated_at
  FROM habit_pauses;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'reward', id,
    CASE WHEN archived_at IS NULL THEN 'upsert' ELSE 'archive' END, updated_at
  FROM rewards;
INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  SELECT user_id, 'habit_reminder', id, 'upsert', updated_at
  FROM habit_reminders;
