class ReminderTime {
  const ReminderTime._(this.hour, this.minute);

  factory ReminderTime.parse(String value) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      throw ArgumentError.value(value, 'timeOfDay', 'Must use HH:mm');
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      throw ArgumentError.value(value, 'timeOfDay', 'Must be a valid time');
    }
    return ReminderTime._(hour, minute);
  }

  final int hour;
  final int minute;

  String get value =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
