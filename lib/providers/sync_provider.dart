// lib/providers/sync_provider.dart
import 'package:flutter/foundation.dart';

class SyncProvider with ChangeNotifier {
  bool _isSyncing = false;
  String _syncMessage = '';
  double _syncProgress = 0.0;

  bool get isSyncing => _isSyncing;
  String get syncMessage => _syncMessage;
  double get syncProgress => _syncProgress;

  void startSync(String message) {
    _isSyncing = true;
    _syncMessage = message;
    _syncProgress = 0.0;
    notifyListeners();
  }

  void updateProgress(double progress, String message) {
    _syncProgress = progress;
    _syncMessage = message;
    notifyListeners();
  }

  void endSync() {
    _isSyncing = false;
    _syncProgress = 1.0;
    notifyListeners();
    Future.delayed(Duration(seconds: 2), () {
      _syncProgress = 0.0;
      notifyListeners();
    });
  }
}