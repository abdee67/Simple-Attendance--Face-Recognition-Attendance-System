class AttendanceException implements Exception {
  final String message;
  final DateTime timestamp;

  AttendanceException(this.message) : timestamp = DateTime.now();

  @override
  String toString() => 'AttendanceException: $message (at $timestamp)';
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => statusCode != null
      ? 'ApiException: $message (Status: $statusCode)'
      : 'ApiException: $message';
}