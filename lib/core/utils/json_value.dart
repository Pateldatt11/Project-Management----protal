/// Defensive readers for Firestore/admin JSON.
///
/// The admin UI can sometimes save a value as a structured map, while the APK
/// model expects a primitive string/list/number. These helpers coerce safely so
/// one malformed profile/task/notification field does not crash the renderer.
class JsonValue {
  const JsonValue._();

  static String string(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    if (value is Map) {
      for (final key in const <String>['value', 'label', 'name', 'title', 'text', 'displayName', 'email', 'uid', 'id', 'companyId']) {
        if (value.containsKey(key)) {
          final nested = string(value[key], fallback: '');
          if (nested.trim().isNotEmpty) return nested;
        }
      }
      return fallback;
    }
    if (value is Iterable) {
      final joined = value.map((item) => string(item, fallback: '')).where((item) => item.trim().isNotEmpty).join(', ');
      return joined.trim().isEmpty ? fallback : joined;
    }
    return value.toString();
  }

  static String? optionalString(dynamic value) {
    final text = string(value, fallback: '').trim();
    return text.isEmpty ? null : text;
  }

  static bool boolean(dynamic value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = string(value, fallback: '').trim().toLowerCase();
    if (text.isEmpty) return fallback;
    if (const {'true', '1', 'yes', 'y', 'online', 'active', 'available', 'enabled'}.contains(text)) return true;
    if (const {'false', '0', 'no', 'n', 'offline', 'inactive', 'busy', 'disabled'}.contains(text)) return false;
    return fallback;
  }

  static num number(dynamic value, {num fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value;
    if (value is Map && value.containsKey('value')) return number(value['value'], fallback: fallback);
    return num.tryParse(string(value, fallback: '').trim()) ?? fallback;
  }

  static int integer(dynamic value, {int fallback = 0}) {
    final parsed = number(value, fallback: fallback);
    return parsed.isNaN ? fallback : parsed.round();
  }

  static Map<String, dynamic>? map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    return null;
  }

  static List<String> stringList(dynamic value) {
    final result = <String>[];

    void add(dynamic raw) {
      if (raw == null) return;
      if (raw is Map) {
        for (final key in const <String>['uid', 'id', 'memberId', 'userId', 'projectId', 'teamId', 'taskId', 'value', 'name', 'label']) {
          if (raw.containsKey(key)) {
            final text = string(raw[key], fallback: '').trim();
            if (text.isNotEmpty) {
              result.add(text);
              return;
            }
          }
        }
        return;
      }
      if (raw is Iterable) {
        for (final item in raw) {
          add(item);
        }
        return;
      }
      final text = string(raw, fallback: '').trim();
      if (text.isEmpty) return;
      if (text.contains(',')) {
        for (final part in text.split(',')) {
          final cleaned = part.trim();
          if (cleaned.isNotEmpty) result.add(cleaned);
        }
      } else {
        result.add(text);
      }
    }

    if (value is Map) {
      // Supports Firestore shapes like {uidA: true, uidB: true} and also
      // structured arrays that accidentally arrive as an object.
      value.forEach((key, mapValue) {
        if (mapValue == true) {
          add(key);
        } else {
          add(mapValue);
        }
      });
    } else {
      add(value);
    }

    return result.where((item) => item.trim().isNotEmpty).toSet().toList();
  }
}
