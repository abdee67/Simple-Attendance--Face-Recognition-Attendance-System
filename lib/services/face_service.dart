import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:simple_attendance/db/dbmethods.dart';
import 'package:simple_attendance/screens/location_service.dart';
import 'package:simple_attendance/services/api_service.dart';

// Add the extension here (before the class)
extension ReshapeList on List {
  List reshape(List<int> shape) {
    if (shape.isEmpty) return this;
    if (shape.length == 1) return this;

    final totalElements = shape.reduce((a, b) => a * b);
    if (totalElements != length) {
      throw ArgumentError('Total elements mismatch in reshape');
    }
    List result = this;
    for (var i = shape.length - 1; i > 0; i--) {
      final newLength = length ~/ shape[i];
      result = List.generate(
        newLength,
        (index) => result.sublist(index * shape[i], (index + 1) * shape[i]),
      );
    }

    return result;
  }
}

class FaceService {
  final ApiService apiService;
  final AttendancedbMethods db;
  final LocationService locationService;
  final Connectivity connectivity;
  // static const String baseUrl = 'https://bf0e-196-188-160-151.ngrok-free.app/savvy/api';

  FaceService({
    required this.apiService,
    required this.db,
    required this.locationService,
    required this.connectivity,
  });

  static Future<Float32List> getFaceEmbedding(String imagePath) async {
    try {
      // Fix output tensor handling
      final output = ReshapeList(List.filled(128, 0.0)).reshape([1, 128]);

      // Convert to Float32List and normalize
      final embedding = Float32List.fromList(output[0]);
      final normalized = normalizeEmbedding(embedding);

      if (normalized.length != 128) {
        throw Exception('Invalid embedding length: ${normalized.length}');
      }
      return normalized;
    } catch (e) {
      rethrow;
    }
  }

  static Float32List normalizeEmbedding(Float32List embedding) {
    // Calculate vector length
    double sum = 0.0;
    for (final value in embedding) {
      sum += value * value;
    }
    final length = sqrt(sum);

    // Normalize to unit vector
    return Float32List.fromList(embedding.map((v) => v / length).toList());
  }

  Future<bool> checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  // 7. Update pending records
  // face_service.dart
  Future<void> syncPendingRecords() async {
    await ApiService().processPendingSyncs();
  }
}
