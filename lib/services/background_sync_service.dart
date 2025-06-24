/*  lib/services/background_sync_service.dart
import 'package:dover/services/sync_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../db/siteDetailDatabase.dart';

class BackgroundSyncService {
  static const String syncTask = 'syncTask';
  static const String lastSyncKey = 'lastSync';
  static late ApiService _apiService;
  static late Database _db;

  static Future<void> initialize({required ApiService apiService, required Database db}) async {
    _apiService = apiService;
    _db = db;
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> callbackDispatcher() async {
    Workmanager().executeTask((task, inputData) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastSync = prefs.getString(lastSyncKey);
        
        if (lastSync == null || 
            DateTime.now().difference(DateTime.parse(lastSync)) > const Duration(minutes: 10)) {
          final syncService = SyncService(_apiService, _db);
          await syncService.processPendingSyncs();
          await prefs.setString(lastSyncKey, DateTime.now().toIso8601String());
        }
        
        return true;
      } catch (e) {
        return false;
      }
    });
  }

  static Future<void> scheduleSync() async {
    await Workmanager().registerPeriodicTask(
      '1',
      syncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}**/