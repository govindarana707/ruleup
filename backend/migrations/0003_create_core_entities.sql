PRAGMA foreign_keys = ON;

CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT,
  UNIQUE(id, user_id)
);

CREATE TABLE habits (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category_id TEXT,
  name TEXT NOT NULL,
  measurement_type TEXT NOT NULL CHECK(measurement_type IN ('yes_no','duration','count','value')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  missed_penalty_enabled INTEGER NOT NULL DEFAULT 0 CHECK(missed_penalty_enabled IN (0,1)),
  missed_penalty_points INTEGER NOT NULL DEFAULT 0 CHECK(missed_penalty_points <= 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT,
  UNIQUE(id, user_id),
  FOREIGN KEY(category_id, user_id) REFERENCES categories(id, user_id)
);

CREATE TABLE habit_options (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id TEXT NOT NULL,
  label TEXT NOT NULL,
  numeric_value REAL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT,
  UNIQUE(id, user_id),
  FOREIGN KEY(habit_id, user_id) REFERENCES habits(id, user_id) ON DELETE CASCADE
);

CREATE TABLE habit_schedules (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id TEXT NOT NULL,
  schedule_type TEXT NOT NULL CHECK(schedule_type IN ('daily','specific_days','times_per_week','custom')),
  schedule_config TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(id, user_id),
  FOREIGN KEY(habit_id, user_id) REFERENCES habits(id, user_id) ON DELETE CASCADE
);

CREATE TABLE point_rules (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id TEXT NOT NULL,
  operator TEXT NOT NULL CHECK(operator IN ('completed','eq','lt','lte','gt','gte','between')),
  value_min REAL,
  value_max REAL,
  points INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT,
  UNIQUE(id, user_id),
  FOREIGN KEY(habit_id, user_id) REFERENCES habits(id, user_id) ON DELETE CASCADE
);

CREATE TABLE check_ins (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id TEXT NOT NULL,
  habit_date TEXT NOT NULL,
  option_id TEXT,
  measured_value REAL,
  note TEXT,
  awarded_points INTEGER NOT NULL,
  matched_rule_id TEXT,
  checked_in_at TEXT NOT NULL,
  editable_until TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(id, user_id),
  UNIQUE(user_id, habit_id, habit_date),
  FOREIGN KEY(habit_id, user_id) REFERENCES habits(id, user_id) ON DELETE CASCADE,
  FOREIGN KEY(option_id, user_id) REFERENCES habit_options(id, user_id),
  FOREIGN KEY(matched_rule_id, user_id) REFERENCES point_rules(id, user_id)
);

CREATE TABLE point_ledger (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK(source_type IN ('check_in','missed_check_in','reward_redemption')),
  source_id TEXT NOT NULL,
  points INTEGER NOT NULL,
  reason TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(id, user_id),
  UNIQUE(user_id, source_type, source_id)
);

CREATE TABLE habit_pauses (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id TEXT NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL CHECK(end_date >= start_date),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(id, user_id),
  FOREIGN KEY(habit_id, user_id) REFERENCES habits(id, user_id) ON DELETE CASCADE
);

CREATE TABLE rewards (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  points_cost INTEGER NOT NULL CHECK(points_cost > 0),
  monetary_cap REAL CHECK(monetary_cap IS NULL OR monetary_cap >= 0),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT,
  UNIQUE(id, user_id)
);

CREATE TABLE habit_reminders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id TEXT NOT NULL,
  enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),
  time_of_day TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(id, user_id),
  UNIQUE(user_id, habit_id),
  FOREIGN KEY(habit_id, user_id) REFERENCES habits(id, user_id) ON DELETE CASCADE
);

CREATE INDEX categories_user_idx ON categories(user_id);
CREATE INDEX habits_user_idx ON habits(user_id);
CREATE INDEX habit_options_user_idx ON habit_options(user_id);
CREATE INDEX habit_schedules_user_idx ON habit_schedules(user_id);
CREATE INDEX point_rules_user_idx ON point_rules(user_id);
CREATE INDEX check_ins_user_idx ON check_ins(user_id);
CREATE INDEX point_ledger_user_idx ON point_ledger(user_id);
CREATE INDEX habit_pauses_user_idx ON habit_pauses(user_id);
CREATE INDEX rewards_user_idx ON rewards(user_id);
CREATE INDEX habit_reminders_user_idx ON habit_reminders(user_id);
