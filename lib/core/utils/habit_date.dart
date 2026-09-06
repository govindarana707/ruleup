DateTime normalizeHabitDate(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
}

String habitDateKey(DateTime date) {
  final normalized = normalizeHabitDate(date);
  final year = normalized.year.toString().padLeft(4, '0');
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime parseHabitDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) throw FormatException('Invalid habit date', value);
  final parsed = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  if (habitDateKey(parsed) != value) {
    throw FormatException('Invalid habit date', value);
  }
  return parsed;
}
