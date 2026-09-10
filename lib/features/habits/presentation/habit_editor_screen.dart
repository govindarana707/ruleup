import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';
import 'package:ruleup/features/points/domain/point_rule_operator.dart';

class HabitEditorScreen extends ConsumerStatefulWidget {
  const HabitEditorScreen({
    super.key,
    required this.userId,
    required this.initialCategories,
    this.habitId,
  });

  final String userId;
  final String? habitId;
  final List<CategoryChoice> initialCategories;

  @override
  ConsumerState<HabitEditorScreen> createState() => _HabitEditorScreenState();
}

class _HabitEditorScreenState extends ConsumerState<HabitEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<CategoryChoice> _categories;
  HabitDraft? _draft;
  Object? _loadError;
  String? _validationError;
  var _saving = false;

  bool get _editing => widget.habitId != null;

  @override
  void initState() {
    super.initState();
    _categories = [...widget.initialCategories];
    if (_editing) {
      _load();
    } else {
      _draft = HabitDraft();
    }
  }

  Future<void> _load() async {
    try {
      final draft = await ref.read(habitDraftLoaderProvider)(
        widget.userId,
        widget.habitId!,
      );
      if (draft.categoryId != null &&
          !_categories.any((item) => item.id == draft.categoryId)) {
        draft.categoryId = null;
      }
      if (mounted) setState(() => _draft = draft);
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: HomeDashboardTheme.create(),
      child: Scaffold(
        key: const Key('habit-editor-screen'),
        appBar: AppBar(
          title: Text(_editing ? 'Edit habit' : 'Create habit'),
          actions: [
            TextButton(
              key: const Key('save-habit-button'),
              onPressed: _draft == null || _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            const Text("Couldn't open this habit"),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    final draft = _draft;
    if (draft == null) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              key: const Key('habit-editor-scroll'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                if (_validationError != null) ...[
                  _InlineMessage(message: _validationError!),
                  const SizedBox(height: 12),
                ],
                _EditorSection(
                  title: 'Basics',
                  subtitle:
                      'Name the routine and decide how progress is measured.',
                  child: Column(
                    children: [
                      TextFormField(
                        key: const Key('habit-name-field'),
                        initialValue: draft.name,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Habit name',
                          hintText: 'Read for 20 minutes',
                        ),
                        onChanged: (value) => draft.name = value,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a habit name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              key: const Key('habit-category-field'),
                              initialValue: draft.categoryId,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Uncategorized'),
                                ),
                                ..._categories.map(
                                  (category) => DropdownMenuItem(
                                    value: category.id,
                                    child: Text(category.name),
                                  ),
                                ),
                              ],
                              onChanged: (value) => draft.categoryId = value,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            key: const Key('add-category-button'),
                            tooltip: 'Create category',
                            onPressed: _createCategory,
                            icon: const Icon(Icons.create_new_folder_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MeasurementType>(
                        key: const Key('measurement-type-field'),
                        initialValue: draft.measurementType,
                        decoration: const InputDecoration(
                          labelText: 'Measurement type',
                        ),
                        items: MeasurementType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(_measurementLabel(type)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => draft.measurementType = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                _EditorSection(
                  title: 'Habit options',
                  subtitle:
                      'Optional quick choices. Use arrows to set their order.',
                  trailing: IconButton(
                    key: const Key('add-option-button'),
                    tooltip: 'Add option',
                    onPressed: () => _editOption(),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  child: draft.options.isEmpty
                      ? const _SectionEmpty('No quick options added.')
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < draft.options.length;
                              index++
                            )
                              _OrderedRow(
                                title: draft.options[index].label,
                                subtitle:
                                    draft.options[index].numericValue.isEmpty
                                    ? null
                                    : 'Value ${draft.options[index].numericValue}',
                                onTap: () => _editOption(index: index),
                                onUp: index == 0
                                    ? null
                                    : () => _move(
                                        draft.options,
                                        index,
                                        index - 1,
                                      ),
                                onDown: index == draft.options.length - 1
                                    ? null
                                    : () => _move(
                                        draft.options,
                                        index,
                                        index + 1,
                                      ),
                                onDelete: () => setState(
                                  () => draft.options.removeAt(index),
                                ),
                              ),
                          ],
                        ),
                ),
                _EditorSection(
                  title: 'Schedule',
                  subtitle:
                      'Only applicable days affect check-ins and streaks.',
                  child: _scheduleEditor(draft),
                ),
                _EditorSection(
                  title: 'Points',
                  subtitle:
                      'Allocate points for completion or measured results.',
                  child: _pointRulesEditor(draft),
                ),
                _EditorSection(
                  title: 'Missed-day penalty',
                  subtitle: 'Optional. Paused and non-scheduled days are never penalized.',
                  child: Column(
                    children: [
                      SwitchListTile(
                        key: const Key('penalty-enabled-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable missed-day penalty'),
                        value: draft.missedPenaltyEnabled,
                        onChanged: (value) =>
                            setState(() => draft.missedPenaltyEnabled = value),
                      ),
                      if (draft.missedPenaltyEnabled)
                        TextFormField(
                          key: const Key('penalty-points-field'),
                          initialValue: draft.missedPenaltyPoints,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Penalty points',
                            helperText: 'Use zero or a negative whole number.',
                          ),
                          onChanged: (value) =>
                              draft.missedPenaltyPoints = value,
                          validator: (value) {
                            if (!draft.missedPenaltyEnabled) return null;
                            final points = int.tryParse(value?.trim() ?? '');
                            return points == null || points > 0
                                ? 'Enter zero or a negative whole number.'
                                : null;
                          },
                        ),
                    ],
                  ),
                ),
                _EditorSection(
                  title: 'Pause periods',
                  subtitle:
                      'Freeze the habit during breaks without losing streaks.',
                  trailing: IconButton(
                    key: const Key('add-pause-button'),
                    tooltip: 'Add pause',
                    onPressed: _addPause,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  child: draft.pauses.isEmpty
                      ? const _SectionEmpty('No pause periods planned.')
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < draft.pauses.length;
                              index++
                            )
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.pause_circle_outline),
                                title: Text(
                                  '${_dateLabel(draft.pauses[index].startDate)} – '
                                  '${_dateLabel(draft.pauses[index].endDate)}',
                                ),
                                onTap: () => _editPause(index),
                                trailing: IconButton(
                                  tooltip: 'Remove pause',
                                  onPressed: () => setState(
                                    () => draft.pauses.removeAt(index),
                                  ),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                          ],
                        ),
                ),
                _EditorSection(
                  title: 'Reminder',
                  subtitle: 'Notification permission is requested safely when needed.',
                  child: Column(
                    children: [
                      SwitchListTile(
                        key: const Key('reminder-enabled-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable reminder'),
                        value: draft.reminderEnabled,
                        onChanged: (value) =>
                            setState(() => draft.reminderEnabled = value),
                      ),
                      if (draft.reminderEnabled)
                        ListTile(
                          key: const Key('reminder-time-button'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.schedule),
                          title: const Text('Reminder time'),
                          trailing: Text(
                            draft.reminderTime,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          onTap: _pickReminderTime,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const Key('save-habit-bottom-button'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(_editing ? 'Save changes' : 'Create habit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scheduleEditor(HabitDraft draft) {
    const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<ScheduleType>(
          key: const Key('schedule-type-field'),
          initialValue: draft.scheduleType,
          decoration: const InputDecoration(labelText: 'Repeats'),
          items: ScheduleType.values
              .map(
                (type) => DropdownMenuItem(
                  value: type,
                  child: Text(_scheduleTypeLabel(type)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) setState(() => draft.scheduleType = value);
          },
        ),
        if (draft.scheduleType == ScheduleType.specificDays) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  label: Text(weekdayNames[day - 1]),
                  selected: draft.scheduleDays.contains(day),
                  onSelected: (selected) => setState(() {
                    selected
                        ? draft.scheduleDays.add(day)
                        : draft.scheduleDays.remove(day);
                  }),
                ),
            ],
          ),
          if (draft.scheduleDays.isEmpty)
            const _FieldError('Choose at least one scheduled day.'),
        ],
        if (draft.scheduleType == ScheduleType.timesPerWeek) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            key: const Key('times-per-week-field'),
            initialValue: draft.timesPerWeek,
            decoration: const InputDecoration(labelText: 'Times per week'),
            items: [
              for (var count = 1; count <= 7; count++)
                DropdownMenuItem(value: count, child: Text('$count')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => draft.timesPerWeek = value);
            },
          ),
        ],
        if (draft.scheduleType == ScheduleType.custom) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final date in draft.customDates)
                InputChip(
                  label: Text(_dateLabel(date)),
                  onDeleted: () =>
                      setState(() => draft.customDates.remove(date)),
                ),
              ActionChip(
                key: const Key('add-custom-date-button'),
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add date'),
                onPressed: _addCustomDate,
              ),
            ],
          ),
          if (draft.customDates.isEmpty)
            const _FieldError('Add at least one custom date.'),
        ],
      ],
    );
  }

  Widget _pointRulesEditor(HabitDraft draft) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.stars_rounded, size: 20, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Point Rules',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const _BestMatchBadge(),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'If more than one rule matches, only the best point result is awarded. Rules never stack.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (draft.measurementType == MeasurementType.count) ...[
          const SizedBox(height: 14),
          const _SmokingRuleExample(),
        ],
        const SizedBox(height: 16),
        if (draft.rules.isEmpty)
          const _SectionEmpty(
            'No point rules yet. Add one to award, deduct, or record zero points.',
          )
        else
          Column(
            children: [
              for (var index = 0; index < draft.rules.length; index++)
                _PointRuleRow(
                  key: ValueKey('point-rule-row-$index'),
                  preview: _rulePreview(draft.rules[index]),
                  onEdit: () => _editRule(index: index),
                  onUp: index == 0
                      ? null
                      : () => _move(draft.rules, index, index - 1),
                  onDown: index == draft.rules.length - 1
                      ? null
                      : () => _move(draft.rules, index, index + 1),
                  onDelete: () => setState(() => draft.rules.removeAt(index)),
                ),
            ],
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('add-rule-button'),
            onPressed: () => _editRule(),
            icon: const Icon(Icons.add),
            label: const Text('Add point rule'),
          ),
        ),
      ],
    );
  }

  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('category-name-field'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Category name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a category name.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-category-button'),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, controller.text);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      final category = await ref.read(categoryCreateActionProvider)(
        widget.userId,
        name,
      );
      setState(() {
        _categories.add(category);
        _categories.sort((a, b) => a.name.compareTo(b.name));
        _draft!.categoryId = category.id;
      });
    } on Object catch (error) {
      setState(() => _validationError = _friendlyError(error));
    }
  }

  Future<void> _editOption({int? index}) async {
    final existing = index == null ? null : _draft!.options[index];
    final label = TextEditingController(text: existing?.label);
    final numeric = TextEditingController(text: existing?.numericValue);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<HabitOptionDraft>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add option' : 'Edit option'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('option-label-field'),
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Label'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an option label.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: numeric,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Numeric value (optional)',
                ),
                validator: (value) =>
                    value != null &&
                        value.trim().isNotEmpty &&
                        double.tryParse(value.trim()) == null
                    ? 'Enter a valid number.'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-option-button'),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(
                  context,
                  HabitOptionDraft(
                    id: existing?.id,
                    label: label.text.trim(),
                    numericValue: numeric.text.trim(),
                  ),
                );
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
    label.dispose();
    numeric.dispose();
    if (result == null || !mounted) return;
    setState(() {
      index == null
          ? _draft!.options.add(result)
          : _draft!.options[index] = result;
    });
  }

  Future<void> _editRule({int? index}) async {
    final existing = index == null ? null : _draft!.rules[index];
    final result = await showDialog<PointRuleDraft>(
      context: context,
      builder: (context) => _PointRuleDialog(
        existing: existing,
        measurementType: _draft!.measurementType,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      index == null ? _draft!.rules.add(result) : _draft!.rules[index] = result;
    });
  }

  Future<void> _addCustomDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    if (_draft!.customDates.any(
      (item) => habitDateKey(item) == habitDateKey(date),
    )) {
      return;
    }
    setState(() => _draft!.customDates.add(date));
  }

  Future<void> _addPause() => _editPause(null);

  Future<void> _editPause(int? index) async {
    final now = DateTime.now();
    final existing = index == null ? null : _draft!.pauses[index];
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: existing?.startDate ?? now,
        end: existing?.endDate ?? now,
      ),
    );
    if (range == null || !mounted) return;
    setState(() {
      final updated = HabitPauseDraft(
        id: existing?.id,
        startDate: range.start,
        endDate: range.end,
      );
      index == null
          ? _draft!.pauses.add(updated)
          : _draft!.pauses[index] = updated;
    });
  }

  Future<void> _pickReminderTime() async {
    final parts = _draft!.reminderTime.split(':').map(int.parse).toList();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
    );
    if (time == null || !mounted) return;
    setState(() {
      _draft!.reminderTime =
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    });
  }

  void _move<T>(List<T> items, int from, int to) {
    setState(() {
      final item = items.removeAt(from);
      items.insert(to, item);
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final draft = _draft!;
    final formsValid = _formKey.currentState?.validate() ?? false;
    final message = draft.validate();
    if (!formsValid || message != null) {
      setState(
        () => _validationError = message ?? 'Review the highlighted fields.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    try {
      await ref.read(habitSaveActionProvider)(widget.userId, draft);
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationError = _friendlyError(error);
        });
      }
    }
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                trailing ?? const SizedBox.shrink(),
              ],
            ),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _OrderedRow extends StatelessWidget {
  const _OrderedRow({
    required this.title,
    required this.onTap,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Move up',
            onPressed: onUp,
            icon: const Icon(Icons.arrow_upward, size: 19),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Move down',
            onPressed: onDown,
            icon: const Icon(Icons.arrow_downward, size: 19),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 19),
          ),
        ],
      ),
    );
  }
}

class _PointRuleDialog extends StatefulWidget {
  const _PointRuleDialog({
    required this.existing,
    required this.measurementType,
  });

  final PointRuleDraft? existing;
  final MeasurementType measurementType;

  @override
  State<_PointRuleDialog> createState() => _PointRuleDialogState();
}

class _PointRuleDialogState extends State<_PointRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _points;
  late PointRuleOperator _operator;

  @override
  void initState() {
    super.initState();
    _operator =
        widget.existing?.operator ??
        (widget.measurementType == MeasurementType.yesNo
            ? PointRuleOperator.completed
            : PointRuleOperator.gte);
    _min = TextEditingController(text: widget.existing?.valueMin);
    _max = TextEditingController(text: widget.existing?.valueMax);
    _points = TextEditingController(text: widget.existing?.points);
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add Point Rule' : 'Edit Point Rule',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<PointRuleOperator>(
                key: const Key('rule-operator-field'),
                initialValue: _operator,
                decoration: const InputDecoration(
                  labelText: 'Condition',
                  helperText: 'Choose when this point result applies.',
                ),
                items: PointRuleOperator.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_operatorLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _operator = value);
                },
              ),
              if (_operator != PointRuleOperator.completed) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('rule-value-min-field'),
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _operator == PointRuleOperator.between
                        ? 'Minimum value'
                        : 'Comparison value',
                    hintText: widget.measurementType == MeasurementType.count
                        ? 'e.g. 10 cigarettes'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      double.tryParse(value?.trim() ?? '') == null
                      ? 'Enter a valid number.'
                      : null,
                ),
              ],
              if (_operator == PointRuleOperator.between) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('rule-value-max-field'),
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Maximum value'),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final maximum = double.tryParse(value?.trim() ?? '');
                    final minimum = double.tryParse(_min.text.trim());
                    if (maximum == null) return 'Enter a valid number.';
                    return minimum != null && minimum > maximum
                        ? 'Maximum must be at least the minimum.'
                        : null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('rule-points-field'),
                controller: _points,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Points',
                  helperText:
                      'Use positive, negative, or zero whole-number points.',
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) => int.tryParse(value?.trim() ?? '') == null
                    ? 'Enter whole-number points.'
                    : null,
              ),
              const SizedBox(height: 12),
              _RuleDialogPreview(
                operator: _operator,
                valueMin: _min.text,
                valueMax: _max.text,
                points: _points.text,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-rule-button'),
          onPressed: _submit,
          child: const Text('Done'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      PointRuleDraft(
        id: widget.existing?.id,
        operator: _operator,
        valueMin: _operator == PointRuleOperator.completed
            ? ''
            : _min.text.trim(),
        valueMax: _operator == PointRuleOperator.between
            ? _max.text.trim()
            : '',
        points: _points.text.trim(),
      ),
    );
  }
}

class _BestMatchBadge extends StatelessWidget {
  const _BestMatchBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('best-match-only-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        'Best Match Only',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SmokingRuleExample extends StatelessWidget {
  const _SmokingRuleExample();

  static const _rules = [
    '≤ 10 cigarettes → +1 point',
    '≤ 5 cigarettes → +2 points',
    '≤ 1 cigarette → +4 points',
    '= 0 cigarettes → +5 points',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('smoking-rule-example'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Smoking example',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final rule in _rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(rule, style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: 6),
          Text(
            '4 cigarettes earns +2 points only — the +1 rule does not stack.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointRuleRow extends StatelessWidget {
  const _PointRuleRow({
    super.key,
    required this.preview,
    required this.onEdit,
    required this.onUp,
    required this.onDown,
    required this.onDelete,
  });

  final String preview;
  final VoidCallback onEdit;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 6),
            child: Text(
              preview,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: colors.onSurface),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Move rule up',
                onPressed: onUp,
                icon: const Icon(Icons.arrow_upward, size: 19),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Move rule down',
                onPressed: onDown,
                icon: const Icon(Icons.arrow_downward, size: 19),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete point rule',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 19),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleDialogPreview extends StatelessWidget {
  const _RuleDialogPreview({
    required this.operator,
    required this.valueMin,
    required this.valueMax,
    required this.points,
  });

  final PointRuleOperator operator;
  final String valueMin;
  final String valueMax;
  final String points;

  @override
  Widget build(BuildContext context) {
    final draft = PointRuleDraft(
      operator: operator,
      valueMin: valueMin,
      valueMax: valueMax,
      points: points,
    );
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('rule-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Preview: ${_rulePreview(draft)}',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: colors.onSurface, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 12),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.error),
    ),
  );
}

String _measurementLabel(MeasurementType type) => switch (type) {
  MeasurementType.yesNo => 'Yes / No completion',
  MeasurementType.duration => 'Duration',
  MeasurementType.count => 'Count',
  MeasurementType.value => 'Numeric value',
};

String _scheduleTypeLabel(ScheduleType type) => switch (type) {
  ScheduleType.daily => 'Every day',
  ScheduleType.specificDays => 'Specific weekdays',
  ScheduleType.timesPerWeek => 'Times per week',
  ScheduleType.custom => 'Custom dates',
};

String _operatorLabel(PointRuleOperator operator) => switch (operator) {
  PointRuleOperator.completed => 'Completed',
  PointRuleOperator.eq => '= Equals',
  PointRuleOperator.lt => '< Less than',
  PointRuleOperator.lte => '≤ Less than or equal',
  PointRuleOperator.gt => '> Greater than',
  PointRuleOperator.gte => '≥ Greater than or equal',
  PointRuleOperator.between => 'Between (inclusive)',
};

String _rulePreview(PointRuleDraft rule) {
  final points = _formatPoints(rule.points);
  return switch (rule.operator) {
    PointRuleOperator.completed => 'Completed → $points',
    PointRuleOperator.eq => '= ${_displayNumber(rule.valueMin)} → $points',
    PointRuleOperator.lt => '< ${_displayNumber(rule.valueMin)} → $points',
    PointRuleOperator.lte => '≤ ${_displayNumber(rule.valueMin)} → $points',
    PointRuleOperator.gt => '> ${_displayNumber(rule.valueMin)} → $points',
    PointRuleOperator.gte => '≥ ${_displayNumber(rule.valueMin)} → $points',
    PointRuleOperator.between =>
      'Between ${_displayNumber(rule.valueMin)} and '
          '${_displayNumber(rule.valueMax)} → $points',
  };
}

String _displayNumber(String value) {
  final number = double.tryParse(value.trim());
  if (number == null) return value.trim().isEmpty ? '…' : value.trim();
  return number == number.truncateToDouble()
      ? number.toInt().toString()
      : number.toString();
}

String _formatPoints(String value) {
  final points = int.tryParse(value.trim());
  if (points == null) return '… points';
  final signed = points > 0 ? '+$points' : '$points';
  return '$signed ${points.abs() == 1 ? 'point' : 'points'}';
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst('ArgumentError: ', '');
  return message.length <= 180 ? message : '${message.substring(0, 177)}…';
}
