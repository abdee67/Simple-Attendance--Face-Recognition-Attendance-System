// lib/utils/parsing_utils.dart

int? parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}


double? parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? boolToInt(bool? value) {
  if (value == null) return null;
  return value ? 1 : 0;
}


bool? parseBool(dynamic value) {
  if (value == null) return null;
  final str = value.toString().toUpperCase();
  return str == 'Y' || str == '1';
}

String? boolToChar(bool? value) {
  if (value == null) return null;
  return value ? 'Y' : 'N';
}
