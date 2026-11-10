/// Lenient JSON coercion helpers.
///
/// Real-world fleet backends are inconsistent: speed arrives as `"42.5"` or
/// `42.5`, ids as `_id` or `id`, booleans as `1`/`"true"`. Rather than
/// scattering try/catch across models, every model funnels through these.
library;

T? pick<T>(Map<String, dynamic> json, List<String> keys) {
  for (final String k in keys) {
    final Object? v = json[k];
    if (v is T) return v;
  }
  return null;
}

String asString(Map<String, dynamic> json, List<String> keys, {String fallback = ''}) {
  for (final String k in keys) {
    Object? v = json[k];
    if (v != null) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num || v is bool) return v.toString();
      if (v is Map && v['\$oid'] is String) return v['\$oid'] as String;
    }
    final String fuzzyK = k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final MapEntry<String, dynamic> entry in json.entries) {
      if (entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == fuzzyK) {
        v = entry.value;
        if (v != null) {
          if (v is String && v.trim().isNotEmpty) return v.trim();
          if (v is num || v is bool) return v.toString();
          if (v is Map && v['\$oid'] is String) return v['\$oid'] as String;
        }
      }
    }
  }
  return fallback;
}

String? asStringOrNull(Map<String, dynamic> json, List<String> keys) {
  final String v = asString(json, keys);
  return v.isEmpty ? null : v;
}

double asDouble(Map<String, dynamic> json, List<String> keys, {double fallback = 0}) {
  for (final String k in keys) {
    Object? v = json[k];
    if (v != null) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final double? p = double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
        if (p != null) return p;
      }
    }
    final String fuzzyK = k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final MapEntry<String, dynamic> entry in json.entries) {
      if (entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == fuzzyK) {
        v = entry.value;
        if (v != null) {
          if (v is num) return v.toDouble();
          if (v is String) {
            final double? p = double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
            if (p != null) return p;
          }
        }
      }
    }
  }
  return fallback;
}

double? asDoubleOrNull(Map<String, dynamic> json, List<String> keys) {
  for (final String k in keys) {
    Object? v = json[k];
    if (v != null) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final double? p = double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
        if (p != null) return p;
      }
    }
    final String fuzzyK = k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final MapEntry<String, dynamic> entry in json.entries) {
      if (entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == fuzzyK) {
        v = entry.value;
        if (v != null) {
          if (v is num) return v.toDouble();
          if (v is String) {
            final double? p = double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
            if (p != null) return p;
          }
        }
      }
    }
  }
  return null;
}

int asInt(Map<String, dynamic> json, List<String> keys, {int fallback = 0}) =>
    asDouble(json, keys, fallback: fallback.toDouble()).round();

bool asBool(Map<String, dynamic> json, List<String> keys, {bool fallback = false}) {
  for (final String k in keys) {
    Object? v = json[k];
    if (v != null) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final String s = v.toLowerCase().trim();
        if (<String>['true', '1', 'on', 'yes', 'active'].contains(s)) return true;
        if (<String>['false', '0', 'off', 'no', 'inactive'].contains(s)) return false;
      }
    }
    final String fuzzyK = k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final MapEntry<String, dynamic> entry in json.entries) {
      if (entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == fuzzyK) {
        v = entry.value;
        if (v != null) {
          if (v is bool) return v;
          if (v is num) return v != 0;
          if (v is String) {
            final String s = v.toLowerCase().trim();
            if (<String>['true', '1', 'on', 'yes', 'active'].contains(s)) return true;
            if (<String>['false', '0', 'off', 'no', 'inactive'].contains(s)) return false;
          }
        }
      }
    }
  }
  return fallback;
}

DateTime? asDate(Map<String, dynamic> json, List<String> keys) {
  for (final String k in keys) {
    final Object? v = json[k];
    if (v == null) continue;
    if (v is DateTime) return v;
    if (v is num) {
      // Heuristic: 10-digit = seconds, 13-digit = milliseconds.
      final int ms = v < 100000000000 ? (v * 1000).round() : v.round();
      return DateTime.fromMillisecondsSinceEpoch(
        ms,
        isUtc: true,
      ).toLocal();
    }
    if (v is String && v.trim().isNotEmpty) {
      String str = v.trim();
      
      // Convert DD-MM-YYYY or DD/MM/YYYY to YYYY-MM-DD
      if (RegExp(r'^\d{2}[-/]\d{2}[-/]\d{4}').hasMatch(str)) {
        str = '${str.substring(6, 10)}-${str.substring(3, 5)}-${str.substring(0, 2)}${str.substring(10)}';
      }

      // If the backend sends UTC without a Z or offset (e.g. "2026-07-30 12:47:00")
      // we append Z, but verify it does not jump into the future if the string was already local.
      final bool hadOffset = str.endsWith('Z') ||
          str.contains('+') ||
          str.contains(RegExp(r'-[0-9]{2}:?[0-9]{2}$'));
      if (!hadOffset) {
        str = str.replaceAll(' ', 'T');
        if (str.contains('T')) {
          str = '${str}Z';
        }
      }
      final DateTime? d = DateTime.tryParse(str);
      if (d != null) {
        final DateTime local = d.toLocal();
        // If appending 'Z' pushed this timestamp more than 5 minutes into the future,
        // the original string was already local time, not UTC.
        if (!hadOffset && local.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
          final String withoutZ = str.replaceAll(RegExp(r'[Zz]$'), '');
          final DateTime? fallbackLocal = DateTime.tryParse(withoutZ);
          if (fallbackLocal != null) return fallbackLocal;
        }
        return local;
      }
      final int? ms = int.tryParse(v);
      if (ms != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          ms < 100000000000 ? ms * 1000 : ms,
          isUtc: true,
        ).toLocal();
      }
    }
    if (v is Map && v['\$date'] != null) {
      return asDate(<String, dynamic>{'d': v['\$date']}, <String>['d']);
    }
  }
  return null;
}

Map<String, dynamic> asMap(Map<String, dynamic> json, List<String> keys) {
  for (final String k in keys) {
    final Object? v = json[k];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asMapList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Object>()
        .map<Map<String, dynamic>?>((Object e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }
  if (value is Map) {
    for (final String key in <String>['data', 'items', 'results', 'docs',
      'rows', 'vehicles', 'records', 'alerts']) {
      if (value[key] is List) return asMapList(value[key]);
    }
  }
  return <Map<String, dynamic>>[];
}

/// Safely coerces any dynamic value (num, String, int, double) to a double, or null.
double? toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  }
  return null;
}

/// Safely coerces any dynamic value to an int, or null.
int? toInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.replaceAll(RegExp(r'[^0-9\-]'), '')) ??
        double.tryParse(value.replaceAll(RegExp(r'[^0-9.\-]'), ''))?.round();
  }
  return null;
}

/// Safely coerces any dynamic value to a num, or null.
num? toNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) {
    return num.tryParse(value.replaceAll(RegExp(r'[^0-9.\-]'), ''));
  }
  return null;
}

