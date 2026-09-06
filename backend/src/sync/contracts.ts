export type FieldType = 'string' | 'number' | 'integer' | 'boolean' | 'date';

export interface FieldContract {
  column: string;
  type: FieldType;
  nullable?: boolean;
  values?: readonly string[];
}

export interface RelationContract {
  field: string;
  table: string;
}

export interface EntityContract {
  table: string;
  fields: Record<string, FieldContract>;
  relations?: readonly RelationContract[];
  archivable?: boolean;
  deletable?: boolean;
  validate?: (data: Record<string, unknown>) => string | null;
}

const baseFields = {
  id: { column: 'id', type: 'string' },
  createdAt: { column: 'created_at', type: 'date' },
  updatedAt: { column: 'updated_at', type: 'date' },
} as const;

const archivedAt = {
  column: 'archived_at',
  type: 'date',
  nullable: true,
} as const;

const habitRelation = [{ field: 'habitId', table: 'habits' }] as const;

export const entityContracts: Record<string, EntityContract> = {
  category: {
    table: 'categories',
    archivable: true,
    fields: {
      ...baseFields,
      name: { column: 'name', type: 'string' },
      sortOrder: { column: 'sort_order', type: 'integer' },
      archivedAt,
    },
  },
  habit: {
    table: 'habits',
    archivable: true,
    relations: [{ field: 'categoryId', table: 'categories' }],
    fields: {
      ...baseFields,
      categoryId: { column: 'category_id', type: 'string', nullable: true },
      name: { column: 'name', type: 'string' },
      measurementType: {
        column: 'measurement_type',
        type: 'string',
        values: ['yes_no', 'duration', 'count', 'value'],
      },
      sortOrder: { column: 'sort_order', type: 'integer' },
      missedPenaltyEnabled: {
        column: 'missed_penalty_enabled',
        type: 'boolean',
      },
      missedPenaltyPoints: {
        column: 'missed_penalty_points',
        type: 'integer',
      },
      archivedAt,
    },
    validate: (data) =>
      Number(data.missedPenaltyPoints) <= 0
        ? null
        : 'missedPenaltyPoints must be zero or negative.',
  },
  habit_option: {
    table: 'habit_options',
    archivable: true,
    relations: habitRelation,
    fields: {
      ...baseFields,
      habitId: { column: 'habit_id', type: 'string' },
      label: { column: 'label', type: 'string' },
      numericValue: { column: 'numeric_value', type: 'number', nullable: true },
      sortOrder: { column: 'sort_order', type: 'integer' },
      archivedAt,
    },
  },
  habit_schedule: {
    table: 'habit_schedules',
    deletable: true,
    relations: habitRelation,
    fields: {
      ...baseFields,
      habitId: { column: 'habit_id', type: 'string' },
      scheduleType: {
        column: 'schedule_type',
        type: 'string',
        values: ['daily', 'specific_days', 'times_per_week', 'custom'],
      },
      scheduleConfig: { column: 'schedule_config', type: 'string' },
    },
    validate: (data) => validJsonObject(data.scheduleConfig),
  },
  point_rule: {
    table: 'point_rules',
    archivable: true,
    relations: habitRelation,
    fields: {
      ...baseFields,
      habitId: { column: 'habit_id', type: 'string' },
      operator: {
        column: 'operator',
        type: 'string',
        values: ['completed', 'eq', 'lt', 'lte', 'gt', 'gte', 'between'],
      },
      valueMin: { column: 'value_min', type: 'number', nullable: true },
      valueMax: { column: 'value_max', type: 'number', nullable: true },
      points: { column: 'points', type: 'integer' },
      sortOrder: { column: 'sort_order', type: 'integer' },
      archivedAt,
    },
    validate: validatePointRule,
  },
  check_in: {
    table: 'check_ins',
    relations: [
      ...habitRelation,
      { field: 'optionId', table: 'habit_options' },
      { field: 'matchedRuleId', table: 'point_rules' },
    ],
    fields: {
      ...baseFields,
      habitId: { column: 'habit_id', type: 'string' },
      habitDate: { column: 'habit_date', type: 'string' },
      optionId: { column: 'option_id', type: 'string', nullable: true },
      measuredValue: {
        column: 'measured_value',
        type: 'number',
        nullable: true,
      },
      note: { column: 'note', type: 'string', nullable: true },
      awardedPoints: { column: 'awarded_points', type: 'integer' },
      matchedRuleId: {
        column: 'matched_rule_id',
        type: 'string',
        nullable: true,
      },
      checkedInAt: { column: 'checked_in_at', type: 'date' },
      editableUntil: { column: 'editable_until', type: 'date' },
    },
    validate: (data) =>
      typeof data.habitDate === 'string' &&
      /^\d{4}-\d{2}-\d{2}$/.test(data.habitDate)
        ? null
        : 'habitDate must use YYYY-MM-DD.',
  },
  point_ledger: {
    table: 'point_ledger',
    fields: {
      ...baseFields,
      sourceType: {
        column: 'source_type',
        type: 'string',
        values: ['check_in', 'missed_check_in', 'reward_redemption'],
      },
      sourceId: { column: 'source_id', type: 'string' },
      points: { column: 'points', type: 'integer' },
      reason: { column: 'reason', type: 'string', nullable: true },
    },
  },
  habit_pause: {
    table: 'habit_pauses',
    deletable: true,
    relations: habitRelation,
    fields: {
      ...baseFields,
      habitId: { column: 'habit_id', type: 'string' },
      startDate: { column: 'start_date', type: 'string' },
      endDate: { column: 'end_date', type: 'string' },
    },
    validate: validatePause,
  },
  reward: {
    table: 'rewards',
    archivable: true,
    fields: {
      ...baseFields,
      name: { column: 'name', type: 'string' },
      pointsCost: { column: 'points_cost', type: 'integer' },
      monetaryCap: { column: 'monetary_cap', type: 'number', nullable: true },
      sortOrder: { column: 'sort_order', type: 'integer' },
      archivedAt,
    },
    validate: (data) => {
      if (Number(data.pointsCost) <= 0) return 'pointsCost must be positive.';
      if (data.monetaryCap != null && Number(data.monetaryCap) < 0) {
        return 'monetaryCap must be zero or positive.';
      }
      return null;
    },
  },
  habit_reminder: {
    table: 'habit_reminders',
    deletable: true,
    relations: habitRelation,
    fields: {
      ...baseFields,
      habitId: { column: 'habit_id', type: 'string' },
      enabled: { column: 'enabled', type: 'boolean' },
      timeOfDay: { column: 'time_of_day', type: 'string' },
    },
    validate: (data) =>
      typeof data.timeOfDay === 'string' &&
      /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(data.timeOfDay)
        ? null
        : 'timeOfDay must use HH:mm.',
  },
};

function validJsonObject(value: unknown): string | null {
  if (typeof value !== 'string') return 'scheduleConfig must be JSON.';
  try {
    const decoded: unknown = JSON.parse(value);
    return decoded && typeof decoded === 'object' && !Array.isArray(decoded)
      ? null
      : 'scheduleConfig must be a JSON object.';
  } catch {
    return 'scheduleConfig must be valid JSON.';
  }
}

function validatePointRule(data: Record<string, unknown>): string | null {
  const operator = data.operator;
  const min = data.valueMin;
  const max = data.valueMax;
  if (operator === 'completed') {
    return min == null && max == null
      ? null
      : 'completed rules cannot have values.';
  }
  if (operator === 'between') {
    return typeof min === 'number' && typeof max === 'number' && min <= max
      ? null
      : 'between rules require ordered minimum and maximum values.';
  }
  return typeof min === 'number' && max == null
    ? null
    : 'Comparison rules require valueMin only.';
}

function validatePause(data: Record<string, unknown>): string | null {
  const start = data.startDate;
  const end = data.endDate;
  if (
    typeof start !== 'string' ||
    typeof end !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}$/.test(start) ||
    !/^\d{4}-\d{2}-\d{2}$/.test(end)
  ) {
    return 'Pause dates must use YYYY-MM-DD.';
  }
  return end >= start ? null : 'endDate must not precede startDate.';
}
