import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:simple_attendance/db/dbHelper.dart';

import '/db/dbmethods.dart';
import '/models/attendance.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';


class ApiService {
  static const String baseUrl = 'https://techequations.com/savvy/api';
  final AttendancedbMethods db = AttendancedbMethods.instance;
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  final Connectivity connectivity = Connectivity();
    final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();


  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  // Authentication Method (returns userId and addresses)
Future<Map<String, dynamic>> authenticateUser(String username, String password) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      final message = jsonData['message'] as String? ?? 'Login successful';
      final userId = jsonData['userId'] as String?;
      if (userId == null || userId.isEmpty) {
        return {
          'success': false,
          'error': 'Authentication succeeded but no user ID was provided',
          'userMessage': 'System error: Please contact support'
        };
      }

      // Store credentials securely for future logins
      await _storeCredentials(username, password, userId);
      
      return {
        'success': true,
        'userId': userId,
        'userMessage': message,
      };
    }
    
    // Handle specific status codes with user-friendly messages
    String userMessage;
    switch (response.statusCode) {
      case 400:
        userMessage = 'Invalid request format';
        break;
      case 401:
        userMessage = 'Incorrect username or password';
        break;
      case 403:
        userMessage = 'Account disabled or access denied';
        break;
      case 404:
        userMessage = 'Account not found';
        break;
      case 500:
        userMessage = 'Server error - please try again later';
        break;
      default:
        userMessage = 'Login failed (Error ${response.statusCode})';
    }
    
    return {
      'success': false,
      'error': userMessage,
      'userMessage': userMessage,
    };
  } on TimeoutException {
    return {
      'success': false,
      'error': 'Connection timeout',
      'userMessage': 'Server took too long to respond. Please check your connection and try again.',
    };
  } on SocketException {
    return {
      'success': false,
      'error': 'Network error',
      'userMessage': 'No internet connection. Please check your network settings.',
    };
  } on FormatException {
    return {
      'success': false,
      'error': 'Invalid server response',
      'userMessage': 'System error: Please contact support',
    };
  } catch (e) {
    return {
      'success': false,
      'error': e.toString(),
      'userMessage': 'An unexpected error occurred. Please try again.',
    };
  }
}
    // Store credentials securely
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<void> _storeCredentials(String username, String password, String? userId) async {
    await _secureStorage.write(key: 'api_username', value: username);
    await _secureStorage.write(key: 'api_password', value: password);
     if (userId != null) {
    await _secureStorage.write(key: 'api_user_id', value: userId);
  }
  }

    // Retrieve stored credentials
Future<Map<String, String>?> getStoredCredentials() async {
  final username = await _secureStorage.read(key: 'api_username');
  final password = await _secureStorage.read(key: 'api_password');
  final userId = await _secureStorage.read(key: 'api_user_id');
  
  if (username != null && password != null) {
    return {
      'username': username, 
      'password': password,
      'userId': userId ?? 'offline_user' // Return empty string if userId is null
    };
  }
  return null;
}
   Future<String?> getUserId() async {
    return await _secureStorage.read(key: 'api_user_id');
  }
  
  Future<void> processPendingSyncs() async {
  
    final pending = await db.getPendingAttendances();
    if (pending.isEmpty) return;
  final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) return;

    for (final record in pending) {
      try {
        final response = await postAttendanceBatch([record]);
        if (response.statusCode == 200) {
          await db.markAsSynced(record.id!);
            final batch = await dbHelper.database;
          await batch.delete(
            'attendance',
            where: 'id = ?',
            whereArgs: [record.id],
          );
        }
      } catch (e) {
        String errorMessage;
        if (e is ApiException) {
          errorMessage = 'API error: ${e.message}';
        } else if (e is SocketException) {
          errorMessage = 'Network error: ${e.message}';
        } else if (e is TimeoutException) {
          errorMessage = 'Request timed out: ${e.message}';
        } else {
          errorMessage = 'Unexpected error: ${e.toString()}';
        }
      }
    }
  }

  /// Sends one or more attendance records in a single batch.
  /// Returns the raw http.Response so callers can decide what to do.
Future<http.Response> postAttendanceBatch(
  List<AttendanceRecord> records, {
  int maxRetries = 3,
}) async {
  // 1) Build your payload exactly as the API expects (an array of objects)
  final List<Map<String, dynamic>> payload = [];
    
    for (final record in records) {
      payload.add(await record.toApiPayload());
    }

  final url = Uri.parse('$baseUrl/attendance/faceCompare');
  final body = jsonEncode(payload);
  http.Response? lastResponse;
  Exception? lastError;

    // 2) Retry loop with exponential backoff
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _client
            .post(url, headers: _headers, body: body)
            .timeout(const Duration(seconds: 30));
        lastResponse = response;
        // 3) Immediately return on success
        if (response.statusCode == 200) {
          return response;
        }
        // 4) Log & prepare to retry
        lastError = ApiException('Status ${response.statusCode}', response.statusCode);
      } on TimeoutException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = Exception('Unknown error: $e');
      }

      // 5) Delay before next attempt (unless it was last)
      if (attempt < maxRetries - 1) {
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }

    // if we have a non‐200 response, return it to caller
    if (lastResponse != null) return lastResponse;

    // else throw the last exception
    throw lastError ?? ApiException('Attendance batch failed after $maxRetries tries');
  }
}

  // Helper method to calculate exponential backoff delay
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => statusCode != null
      ? 'ApiException: $message (Status: $statusCode)'
      : 'ApiException: $message';
}