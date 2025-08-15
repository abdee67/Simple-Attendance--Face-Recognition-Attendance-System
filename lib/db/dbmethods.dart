// Location CRUD

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:simple_attendance/models/attendance.dart';
import '/services/face_service.dart';
import 'package:sqflite/sqflite.dart';
import '/db/dbHelper.dart';

class AttendancedbMethods {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  static final AttendancedbMethods _instance = AttendancedbMethods._internal();
  AttendancedbMethods._internal();
  static AttendancedbMethods get instance => _instance;

  // Attendance CRUD
  Future<int> saveAttendance({
    required String userId,
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    required String imagePath,
    bool synced = false,
  }) async {
    final db = await dbHelper.database;
    return db.insert('attendance', {
      'userId': userId,
      'timestamp': timestamp.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'face_embedding': imagePath,
      'is_synced': 0,
    });
  }

  Future<List<AttendanceRecord>> getPendingAttendances() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      'attendance',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
    return maps
        .map(
          (map) => AttendanceRecord(
            id: map['id'] as int,
            userId: map['userId'] as String,
            timestamp: DateTime.parse(map['timestamp'] as String),
            faceEmbedding: map['face_embedding'] as String,
            latitude: map['latitude'] as double,
            longitude: map['longitude'] as double,
          ),
        )
        .toList();
  }

  Future<void> markAsSynced(int id) async {
    final dbase = await dbHelper.database;
    await dbase.update(
      'attendance',
      {'is_synced': 1},
      where: 'id  = ? AND is_synced = 0 ',
      whereArgs: [id],
    );
  }

  Future<void> saveFaceEmbedding(Float32List embedding) async {
    final db = await dbHelper.database;

    if (embedding.length != 128) {
      throw Exception(
        'Invalid embedding length before save: ${embedding.length}',
      );
    }

    final normalized = FaceService.normalizeEmbedding(embedding);

    // Convert Float32List to Uint8List safely
    final bytes = normalized.buffer.asUint8List();

    // Encode as Base64 string
    final base64Str = base64Encode(bytes);
    await db.insert('attendance', {'face_embeddings': base64Str});
  }

  // Add these methods to Sitedetaildatabase class
  Future<bool> checkUserExists(String username) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    return result.isNotEmpty;
  }

  Future<bool> validateUser(String username, String password) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    return result.isNotEmpty;
  }

  Future<int> insertUser(
    String username,
    String password, {
    String? userId,
  }) async {
    final db = await dbHelper.database;
    return db.insert('users', {
      'username': username,
      'password': password,
      'userId': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updatePassword(String userId, String newPassword) async {
    final db = await dbHelper.database;
    return db.update(
      'users',
      {'password': newPassword},
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }

  Future<Map<String, dynamic>?> getUser(String username) async {
    final db = await dbHelper.database;
    final results = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllLocaion() async {
    final db = await dbHelper.database;
    return await db.query('attendance');
  }

  Future<String?> getUserPassword(String username) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['password'] as String? : null;
  }
}
