import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/core/utils/habit_date.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';
import 'package:ruleup/features/habits/domain/schedule_type.dart';
import 'package:ruleup/features/habits/presentation/habit_management_provider.dart';
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
    return Scaffold(
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
                  title: 'Point rules',
                  subtitle: 'The best matching rule awards one point result.',
                  trailing: IconButton(
                    key: const Key('add-rule-button'),
                    tooltip: 'Add point rule',
                    onPressed: () => _editRule(),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  child: draft.rules.isEmpty
                      ? const _SectionEmpty('No point rules yet.')
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < draft.rules.length;
                              index++
                            )
                              _OrderedRow(
                                title: _ruleLabel(draft.rules[index]),
                                subtitle: '${draft.rules[index].points} points',
                                onTap: () => _editRule(index: index),
                                onUp: index == 0
                                    ? null
                                    : () =>
                                          _move(draft.rules, index, index - 1),
                                onDown: index == draft.rules.length - 1
                                    ? null
                                    : () =>
                                          _move(draft.rules, index, index + 1),
                                onDelete: () =>
                                    setState(() => draft.rules.removeAt(index)),
                              ),
                          ],
                        ),
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
    var operator =
        existing?.operator ??
        (_draft!.measurementType == MeasurementType.yesNo
            ? PointRuleOperator.completed
            : PointRuleOperator.gte);
    final min = TextEditingController(text: existing?.valueMin);
    final max = TextEditingController(text: existing?.valueMax);
    final points = TextEditingController(text: existing?.points);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<PointRuleDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add point rule' : 'Edit point rule'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<PointRuleOperator>(
                    key: const Key('rule-operator-field'),
                    initialValue: operator,
                    decoration: const InputDecoration(labelText: 'When'),
                    items: PointRuleOperator.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_operatorLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => operator = value);
                    },
                  ),
                  if (operator != PointRuleOperator.completed) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('rule-value-min-field'),
                      controller: min,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: operator == PointRuleOperator.between
                            ? 'Minimum value'
                            : 'Comparison value',
                      ),
                      validator: (value) =>
                          double.tryParse(value?.trim() ?? '') == null
                          ? 'Enter a valid number.'
                          : null,
                    ),
                  ],
                  if (operator == PointRuleOperator.between) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('rule-value-max-field'),
                      controller: max,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Maximum value',
                      ),
                      validator: (value) {
                        final maximum = double.tryParse(value?.trim() ?? '');
                        final minimum = double.tryParse(min.text.trim());
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
                    controller: points,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Points'),
                    validator: (value) =>
                        int.tryParse(value?.trim() ?? '') == null
                        ? 'Enter whole-number points.'
                        : null,
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
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    PointRuleDraft(
                      id: existing?.id,
                      operator: operator,
                      valueMin: operator == PointRuleOperator.completed
                          ? ''
                          : min.text.trim(),
                      valueMax: operator == PointRuleOperator.between
                          ? max.text.trim()
                          : '',
                      points: points.text.trim(),
                    ),
                  );
                }
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    min.dispose();
    max.dispose();
    points.dispose();
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
  PointRuleOperator.eq => 'Equals',
  PointRuleOperator.lt => 'Less than',
  PointRuleOperator.lte => 'Less than or equal',
  PointRuleOperator.gt => 'Greater than',
  PointRuleOperator.gte => 'Greater than or equal',
  PointRuleOperator.between => 'Between',
};

String _ruleLabel(PointRuleDraft rule) {
  final operator = _operatorLabel(rule.operator);
  if (rule.operator == PointRuleOperator.completed) return operator;
  if (rule.operator == PointRuleOperator.between) {
    return '$operator ${rule.valueMin} and ${rule.valueMax}';
  }
  return '$operator ${rule.valueMin}';
}

String _dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst('ArgumentError: ', '');
  return message.length <= 180 ? message : '${message.substring(0, 177)}…';
}
