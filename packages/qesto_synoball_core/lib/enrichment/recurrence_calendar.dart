import '../core/models.dart';

/// Calendar-based cadence shared by detected and user-scheduled payments.
/// Every occurrence is advanced from the original anchor so February never
/// permanently changes a 30th/31st-of-month schedule into the 28th.
DateTime advanceOccurrence(
  DateTime anchor,
  RecurrenceFrequency frequency, [
  int cycles = 1,
]) {
  if (cycles < 0) throw ArgumentError.value(cycles, 'cycles');
  if (frequency == RecurrenceFrequency.weekly ||
      frequency == RecurrenceFrequency.biweekly) {
    final days = (frequency == RecurrenceFrequency.weekly ? 7 : 14) * cycles;
    return anchor.isUtc
        ? DateTime.utc(
            anchor.year,
            anchor.month,
            anchor.day + days,
            anchor.hour,
            anchor.minute,
            anchor.second,
            anchor.millisecond,
            anchor.microsecond,
          )
        : DateTime(
            anchor.year,
            anchor.month,
            anchor.day + days,
            anchor.hour,
            anchor.minute,
            anchor.second,
            anchor.millisecond,
            anchor.microsecond,
          );
  }
  final months = switch (frequency) {
    RecurrenceFrequency.monthly => cycles,
    RecurrenceFrequency.bimonthly => 2 * cycles,
    RecurrenceFrequency.quarterly => 3 * cycles,
    RecurrenceFrequency.halfYearly => 6 * cycles,
    RecurrenceFrequency.yearly => 12 * cycles,
    _ => throw ArgumentError.value(frequency, 'frequency'),
  };
  final target = DateTime.utc(anchor.year, anchor.month + months);
  final following = DateTime.utc(target.year, target.month + 1);
  final lastDay = following.subtract(const Duration(days: 1)).day;
  final day = anchor.day > lastDay ? lastDay : anchor.day;
  return anchor.isUtc
      ? DateTime.utc(
          target.year,
          target.month,
          day,
          anchor.hour,
          anchor.minute,
          anchor.second,
          anchor.millisecond,
          anchor.microsecond,
        )
      : DateTime(
          target.year,
          target.month,
          day,
          anchor.hour,
          anchor.minute,
          anchor.second,
          anchor.millisecond,
          anchor.microsecond,
        );
}

DateTime nextOccurrenceOnOrAfter(
  DateTime anchor,
  RecurrenceFrequency frequency,
  DateTime today,
) {
  final targetDay = DateTime.utc(today.year, today.month, today.day);
  final anchorDay = DateTime.utc(anchor.year, anchor.month, anchor.day);
  final stride = switch (frequency) {
    RecurrenceFrequency.weekly => 7,
    RecurrenceFrequency.biweekly => 14,
    _ => 0,
  };
  final monthStride = switch (frequency) {
    RecurrenceFrequency.monthly => 1,
    RecurrenceFrequency.bimonthly => 2,
    RecurrenceFrequency.quarterly => 3,
    RecurrenceFrequency.halfYearly => 6,
    RecurrenceFrequency.yearly => 12,
    _ => 0,
  };
  if (stride == 0 && monthStride == 0) {
    throw ArgumentError.value(frequency, 'frequency');
  }
  var cycles = stride > 0
      ? targetDay.difference(anchorDay).inDays ~/ stride
      : ((today.year - anchor.year) * 12 + today.month - anchor.month) ~/
            monthStride;
  if (cycles < 0) cycles = 0;
  for (; ; cycles++) {
    final candidate = advanceOccurrence(anchor, frequency, cycles);
    final candidateDay = DateTime.utc(
      candidate.year,
      candidate.month,
      candidate.day,
    );
    if (!candidateDay.isBefore(targetDay)) return candidate;
  }
}
