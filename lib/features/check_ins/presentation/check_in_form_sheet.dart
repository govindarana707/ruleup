import 'package:flutter/material.dart';
import 'package:ruleup/features/check_ins/presentation/daily_check_in_provider.dart';
import 'package:ruleup/features/habits/domain/measurement_type.dart';

class CheckInFormSheet extends StatefulWidget {
  const CheckInFormSheet({
    super.key,
    required this.habit,
    required this.habitDate,
    required this.onSubmit,
  });

  final DailyHabitEntry habit;
  final DateTime habitDate;
  final Future<CheckInSubmitResult> Function(CheckInSubmission submission)
  onSubmit;

  @override
  State<CheckInFormSheet> createState() => _CheckInFormSheetState();
}

class _CheckInFormSheetState extends State<CheckInFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _valueController;
  late final TextEditingController _noteController;
  String? _selectedOptionId;
  String? _error;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.habit.checkIn;
    _selectedOptionId = existing?.optionId;
    _valueController = TextEditingController(
      text: existing?.measuredValue?.toString() ?? '',
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isYesNo = widget.habit.measurementType == MeasurementType.yesNo;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            key: const Key('check-in-form-sheet'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.habit.checkIn == null ? 'Check in' : 'Edit check-in',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(widget.habit.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  isYesNo
                      ? 'Mark this habit complete for today.'
                      : _inputPrompt(widget.habit.measurementType),
                  style: theme.textTheme.bodyMedium,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!),
                  ),
                ],
                if (widget.habit.options.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Quick options', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.habit.options
                        .map(
                          (option) => ChoiceChip(
                            key: Key('check-in-option-${option.id}'),
                            label: Text(option.label),
                            selected: _selectedOptionId == option.id,
                            onSelected: (selected) => setState(() {
                              _selectedOptionId = selected ? option.id : null;
                              if (selected) _valueController.clear();
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (!isYesNo) ...[
                  const SizedBox(height: 18),
                  TextFormField(
                    key: const Key('check-in-value-field'),
                    controller: _valueController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal:
                          widget.habit.measurementType != MeasurementType.count,
                    ),
                    decoration: InputDecoration(
                      labelText: _valueLabel(widget.habit.measurementType),
                      helperText: widget.habit.options.isEmpty
                          ? null
                          : 'Or enter a custom value.',
                    ),
                    onChanged: (value) {
                      if (value.trim().isNotEmpty &&
                          _selectedOptionId != null) {
                        setState(() => _selectedOptionId = null);
                      }
                    },
                    validator: _validateValue,
                  ),
                ],
                const SizedBox(height: 18),
                TextFormField(
                  key: const Key('check-in-note-field'),
                  controller: _noteController,
                  maxLines: 2,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'Anything worth remembering?',
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('submit-check-in-button'),
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      widget.habit.checkIn == null
                          ? 'Complete check-in'
                          : 'Update check-in',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validateValue(String? rawValue) {
    if (widget.habit.measurementType == MeasurementType.yesNo ||
        _selectedOptionId != null) {
      return null;
    }
    final value = double.tryParse(rawValue?.trim() ?? '');
    if (value == null || !value.isFinite) return 'Enter a valid value.';
    if (widget.habit.measurementType == MeasurementType.count &&
        value != value.roundToDouble()) {
      return 'Count must be a whole number.';
    }
    if ((widget.habit.measurementType == MeasurementType.count ||
            widget.habit.measurementType == MeasurementType.duration) &&
        value < 0) {
      return 'Value cannot be negative.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final rawValue = _valueController.text.trim();
    try {
      final result = await widget.onSubmit(
        CheckInSubmission(
          habitId: widget.habit.id,
          habitDate: widget.habitDate,
          checkInId: widget.habit.checkIn?.id,
          optionId: _selectedOptionId,
          measuredValue:
              widget.habit.measurementType == MeasurementType.yesNo ||
                  _selectedOptionId != null ||
                  rawValue.isEmpty
              ? null
              : double.parse(rawValue),
          note: _noteController.text,
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _friendlyError(error);
        });
      }
    }
  }
}

String _inputPrompt(MeasurementType type) => switch (type) {
  MeasurementType.yesNo => 'Mark this habit complete for today.',
  MeasurementType.duration => 'How long did you spend?',
  MeasurementType.count => 'How many did you complete?',
  MeasurementType.value => 'What value did you reach?',
};

String _valueLabel(MeasurementType type) => switch (type) {
  MeasurementType.yesNo => 'Completed',
  MeasurementType.duration => 'Duration (minutes)',
  MeasurementType.count => 'Count',
  MeasurementType.value => 'Value',
};

String _friendlyError(Object error) {
  final message = error
      .toString()
      .replaceFirst('ArgumentError: ', '')
      .replaceFirst('CheckInLockedException', 'This check-in is now locked');
  return message.length <= 180 ? message : '${message.substring(0, 177)}…';
}
