import 'package:flutter/material.dart';

/// Keeps Chinese product time input independent from the device's 12-hour UI.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    helpText: helpText,
    builder: appTimePickerBuilder,
  );
}

Widget appTimePickerBuilder(BuildContext context, Widget? child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child ?? const SizedBox.shrink(),
  );
}

String formatAppTime(int minuteOfDay) {
  final safeMinute = minuteOfDay.clamp(0, 23 * 60 + 59);
  return '${(safeMinute ~/ 60).toString().padLeft(2, '0')}:'
      '${(safeMinute % 60).toString().padLeft(2, '0')}';
}

String formatAppTimeOfDay(TimeOfDay time) =>
    formatAppTime(time.hour * 60 + time.minute);
