import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:simple_attendance/services/api_service.dart';
import 'package:simple_attendance/services/face_service.dart';
import 'package:simple_attendance/services/notification_service.dart';

import 'db/dbmethods.dart';
import 'providers/sync_provider.dart';
import 'screens/login.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  await FaceService.init();
  final apiService = ApiService();
  final database = AttendancedbMethods.instance;
  final notificationService = NotificationService();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize notifications
  await notificationService.initialize();
  await notificationService.resetAndReschedule();
  await notificationService.checkPermissions();

  // Process any pending syncs
  await apiService.processPendingSyncs();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SyncProvider()),
        Provider(create: (_) => database),
        Provider(create: (_) => apiService),
        Provider(create: (_) => notificationService),
      ],
      child: const AttendanceApp(),
    ),
  );
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    // Check location permission after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        final result = await Permission.location.request();
        if (!result.isGranted) {
          _showLocationPermissionDialog();
        }
      }
    });
  }

  void _showLocationPermissionDialog() {
    // Use Navigator.of(context, rootNavigator: true) to show dialog from anywhere
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Location Permission Required'),
            content: const Text(
              'This app needs location access to verify your attendance. '
              'Please enable location services in settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = 0xFF1976D2;
    const swatch = <int, Color>{
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
        primarySwatch: const MaterialColor(primary, swatch),
        useMaterial3: true, // Consider using Material 3
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LoginScreen(
        apiService: Provider.of<ApiService>(context, listen: false),
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
