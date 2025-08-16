
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as LocationService;
import 'package:simple_attendance/services/notification_service.dart';

import '/services/face_service.dart';

import '/db/dbmethods.dart';
import '/providers/sync_provider.dart';
import '/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/screens/login.dart';
//import 'screens/siteEntry.dart';

// Import ItemDatabase
// Import DatabaseHelper

void main() async {
    final apiService = ApiService();
     final database = AttendancedbMethods.instance;
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await FaceService.init();
   await apiService.processPendingSyncs();
   final notificationService = NotificationService();
  await notificationService.initialize();
  // After successful login
  // In your main.dart or wherever you initialize your database

  runApp( MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        Provider(create: (_) => database),
        Provider(create: (_) => apiService),
      ],
      child: AttendanceApp (apiService: apiService),
    ),

  );
    Timer.periodic(const Duration(seconds: 15), (timer) async {
    final db = await AttendancedbMethods.instance.dbHelper.database;
  });
}


class AttendanceApp  extends StatefulWidget {
  final ApiService apiService;

  const AttendanceApp ({super.key, required this.apiService});

  @override
  _AttendanceAppState createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp >
    with WidgetsBindingObserver {
  final AttendancedbMethods db = AttendancedbMethods.instance;

  @override
  void initState() {
    super.initState();
    _checkLocationPermissions();
  }
  Future<void> _checkLocationPermissions() async {
    var status = await LocationService.Permission.location.status;
    if (!status.isGranted) {
      status = await LocationService.Permission.location.request();
    }
    bool hasPermission = status.isGranted;
    
    if (!hasPermission) {
      _showLocationPermissionDialog();
    }
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Permission Required'),
        content: Text(
          'This app needs location access to verify your attendance. '
          'Please enable location services in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocationService.openAppSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define your primary color and swatch
    const int primary = 0xFF1976D2; // Example blue color
    const Map<int, Color> swatch = {
      50: Color(0xFFE3F2FD),
      100: Color(0xFFBBDEFB),
      200: Color(0xFF90CAF9),
      300: Color(0xFF64B5F6),
      400: Color(0xFF42A5F5),
      500: Color(0xFF2196F3),
      600: Color(0xFF1E88E5),
      700: Color(0xFF1976D2),
      800: Color(0xFF1565C0),
      900: Color(0xFF0D47A1),
    };

    return MaterialApp(
      title: 'Savvy Attendance',
      theme: ThemeData(
        primarySwatch: MaterialColor(primary, swatch),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LoginScreen(apiService: widget.apiService),
      debugShowCheckedModeBanner: false,
    );
  }

}

