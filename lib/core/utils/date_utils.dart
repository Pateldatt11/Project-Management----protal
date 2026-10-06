import 'package:intl/intl.dart';

class DateText {
  static String compact(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy').format(date);
  }

  static String month(DateTime date) => DateFormat('MMM yyyy').format(date);

  static DateTime? parse(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is Map) {
      for (final key in const <String>['value', 'date', 'iso', 'timestamp']) {
        if (!value.containsKey(key)) continue;
        final nested = parse(value[key]);
        if (nested != null) return nested;
      }
      final seconds = value['seconds'];
      if (seconds is num) return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
      return null;
    }
    try {
      final dynamic converted = value.toDate();
      if (converted is DateTime) return converted;
    } catch (_) {}
    return null;
  }
}
