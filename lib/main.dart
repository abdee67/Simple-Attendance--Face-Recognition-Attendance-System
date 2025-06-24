
import 'dart:async';

import 'package:permission_handler/permission_handler.dart' as LocationService;

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
  await FaceService.init();
   await apiService.processPendingSyncs();
    await database.printAllNozzles();
   
    

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
    return MaterialApp(
      title: 'SmartAttendance',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LoginScreen(apiService: widget.apiService),
      debugShowCheckedModeBanner: false,
    );
  }

}

