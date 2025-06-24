
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

class AttendanceRecord {
  int? id;
  final String userId;
  final String faceEmbedding;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  bool isSynced;

  AttendanceRecord({
    this.id,
    required this.userId,
    required this.timestamp,
    this.isSynced = false,
    required this.faceEmbedding,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> tomap() {
    return {
      'id': id,
      'userId': userId,
      'timestamp': timestamp,
      'is_synced': isSynced ? 1 : 0,
      'face_embedding': faceEmbedding,
      'latitude': latitude,
      'longitude': longitude,

    };
  }

  // attendance.dart
factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
  return AttendanceRecord(
    id: map['id'],
    userId: map['userId'],
    timestamp: DateTime.parse(map['timestamp'] as String), // Ensure parsing
    isSynced: map['is_synced'] == 1,
    faceEmbedding: map['face_embedding'],
    latitude: map['latitude'] as double,
    longitude: map['longitude'] as double,
  );
}
     // Convert to API format
  Future<Map<String, dynamic>> toApiPayload() async {
    final imageBytes = await File(faceEmbedding).readAsBytes();
    final base64Image = base64Encode(imageBytes);
    
    return {
      "userId": userId,
      "attendanceDate": DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(timestamp),
      "latitude": latitude.toString(),
      "longitude": longitude.toString(),
      "employeePhoto": {
        "filename": "attendance_$userId.jpg",
        "fileData": base64Image,
      },
    };
  }
}