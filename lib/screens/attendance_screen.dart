// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:simple_attendance/db/dbmethods.dart';
import 'package:simple_attendance/models/attendance.dart';
import 'package:simple_attendance/screens/login.dart';

import 'package:simple_attendance/services/api_service.dart';

class AttendanceScreen extends StatefulWidget {
  final String userId;

  const AttendanceScreen({super.key, required this.userId});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _isSubmitting = false;
  String? _capturedImagePath;
  String _statusMessage = 'Initializing camera...';
  int _retryCount = 0;
  bool _showRetryButton = false;
  Position? _currentPosition;
  final db = AttendancedbMethods.instance;
  bool _showPreview = false;
  StreamSubscription? _connectivitySubscription;
  final ApiService apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _setupConnectivityListener();
    _initializeDesktopCamera();
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _connectivitySubscription?.cancel();
    // Clean up temporary files
    if (_capturedImagePath != null) {
      try {
        File(_capturedImagePath!).delete();
      } catch (e) {
        if (kDebugMode) {}
      }
    }
    super.dispose();
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) {
      if (result != ConnectivityResult.none) {
        _initSync();
      }
    });
  }

  Future<void> _initSync() async {
    // Wait a bit to let the UI initialize
    await Future.delayed(const Duration(milliseconds: 500));

    // Check for pending sync
    final pendingCount = await db.getPendingAttendances();

    if (pendingCount.isNotEmpty) {
      _showSyncInProgress();
      await ApiService().processPendingSyncs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Unsent attendances are sent to admin! All good!'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      _hideSyncInProgress();
    }
  }

  void _showSyncInProgress() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sending pending attendances...'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _hideSyncInProgress() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _resetCaptureProcess() {
    // Clean up any existing files
    if (_capturedImagePath != null) {
      try {
        File(_capturedImagePath!).delete();
        _capturedImagePath = null;
      } catch (e) {
        if (kDebugMode) {}
      }
    }

    // Reset status message for Windows
    setState(() {
      _statusMessage = 'Camera ready - Click the camera button to take a photo';
    });
  }

  Future<void> _initializeDesktopCamera() async {
    try {
      // Desktop cameras might need different handling
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera detected');
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController.initialize();

      // For Windows, we'll use manual capture only (no automatic face detection)
      setState(() {
        _isCameraInitialized = true;
        _statusMessage =
            'Camera ready - Click the camera button to take a photo';
      });

      // Start Windows capture mode
      _startWindowsCaptureMode();
    } catch (e) {
      debugPrint('Camera initialization failed: $e');
      setState(() => _statusMessage = 'Failed to initialize camera: $e');
      throw Exception('Camera initialization failed: $e');
    }
  }

  // Windows-specific capture mode without image streaming
  void _startWindowsCaptureMode() {
    setState(() {
      _statusMessage = 'Camera ready - Click the camera button to take a photo';
    });
  }

  // Manual capture method for Windows (when image streaming is not supported)
  Future<void> _manualCaptureForWindows() async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
      _statusMessage = 'Capturing photo...';
    });

    try {
      // Take the picture
      final XFile picture = await _cameraController.takePicture();
      final bytes = await picture.readAsBytes();
      img.Image originalImage = img.decodeImage(bytes)!;

      if (_cameraController.description.lensDirection ==
          CameraLensDirection.front) {
        originalImage = img.flipHorizontal(originalImage);
      }

      // Save the captured image
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/attendance_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File faceFile = File(filePath)
        ..writeAsBytesSync(img.encodeJpg(originalImage, quality: 90));

      setState(() {
        _capturedImagePath = faceFile.path;
        _showPreview = true;
        _statusMessage = 'Photo captured! Review and confirm to continue';
      });
    } catch (e, stack) {
      setState(() => _statusMessage = 'Capture failed. Try again.$stack');
      _resetCaptureProcess();
    } finally {
      _isCapturing = false;
    }
  }

  void _handlePreviewAccept() {
    setState(() {
      _showPreview = false;
      _statusMessage = 'Photo accepted! Now acquiring location...';
    });
    _getCurrentLocation();
  }

  void _handlePreviewReject() {
    setState(() {
      _showPreview = false;
      _statusMessage = 'Photo rejected. Click the camera button to try again.';
    });

    // Delete the rejected image
    if (_capturedImagePath != null) {
      File(_capturedImagePath!).delete();
      _capturedImagePath = null;
    }

    // For Windows, no need to restart image stream
    // For mobile platforms, restart the camera stream if needed
    if (_isCameraInitialized &&
        _cameraController.supportsImageStreaming() &&
        !_cameraController.value.isStreamingImages) {
      _cameraController.startImageStream((image) {});
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _statusMessage = 'Checking location service...';
        _showRetryButton = false;
      });

      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(
          () =>
              _statusMessage =
                  'Please enable Location Services in Windows Settings',
        );
        // For Windows, show a more helpful message
        await Future.delayed(const Duration(seconds: 3));
        setState(
          () =>
              _statusMessage =
                  'You can enable location in Windows Settings > Privacy > Location',
        );
        await Future.delayed(const Duration(seconds: 3));
        throw Exception(
          'Location services are disabled. Please enable them in Windows Settings.',
        );
      }

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Requesting location permission...');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception(
            'Location permission denied. Please allow location access.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(
          () =>
              _statusMessage =
                  'Location permission permanently denied. Please enable in Windows Settings.',
        );
        await Future.delayed(const Duration(seconds: 3));
        throw Exception(
          'Location permissions permanently denied. Please enable in Windows Settings > Privacy > Location.',
        );
      }

      // Get current position with timeout
      setState(() => _statusMessage = 'Acquiring location...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      setState(() {
        _currentPosition = position;
        _statusMessage = 'Location acquired! Submitting attendance...';
      });

      await _submitAttendance();
    } catch (e) {
      String errorMsg = 'Location error: ${e.toString()}';
      if (e.toString().contains('denied')) {
        errorMsg =
            'Location permission denied. Please enable location access in Windows Settings > Privacy > Location';
      } else if (e.toString().contains('timeout')) {
        errorMsg = 'Location acquisition timed out. Please try again.';
      }

      setState(() => _statusMessage = errorMsg);
      _showRetryButton = true;
    }
  }

  Future<void> _submitAttendance() async {
    setState(() {
      _isSubmitting = true;
      _statusMessage = 'Submitting attendance...';
    });

    try {
      final isOnline =
          await Connectivity().checkConnectivity() != ConnectivityResult.none;
      final permanentFile = await _createPermanentCopy(_capturedImagePath!);
      final apiService = ApiService();

      final record = AttendanceRecord(
        userId: widget.userId,
        timestamp: DateTime.now(),
        faceEmbedding: permanentFile.path,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      );

      if (isOnline) {
        try {
          final response = await apiService.postAttendanceBatch([record]);
          if (response.statusCode == 200) {
            await apiService.processPendingSyncs();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '✅ Attendance sent successfully, ${record.userId}!',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => LoginScreen(apiService: apiService),
                ),
                (Route<dynamic> route) => false,
              );
            }
            return;
          } else {
            setState(
              () =>
                  _statusMessage =
                      'Failed to submit attendance: ${response.statusCode}',
            );
          }
        } catch (e, stackTrace) {
          setState(() => _statusMessage = 'Submission error: $e\n$stackTrace');
        }
      }
      await _saveAttendanceLocally(record);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${record.userId},Your today attendance saved on your device for now.will send to admin later',
            ),
            duration: const Duration(seconds: 7),
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => LoginScreen(apiService: apiService),
          ),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      String errorMessage = 'Submission error';
      if (e is SocketException) {
        errorMessage = 'No internet connection';
      } else if (e is http.ClientException) {
        errorMessage = 'Server connection failed';
      } else if (e is FormatException) {
        errorMessage = 'Data format error';
      }
      setState(() => _statusMessage = '$errorMessage: ${e.toString()}');
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<File> _createPermanentCopy(String tempPath) async {
    final tempFile = File(tempPath);
    final permanentDir = await getApplicationDocumentsDirectory();
    final permanentPath =
        '${permanentDir.path}/attendance_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await tempFile.copy(permanentPath);
  }

  Future<void> _saveAttendanceLocally(AttendanceRecord record) async {
    await db.saveAttendance(
      userId: record.userId,
      timestamp: record.timestamp,
      imagePath: record.faceEmbedding,
      latitude: record.latitude,
      longitude: record.longitude,
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: 40,
      left: 20,
      child: CircleAvatar(
        backgroundColor: Colors.black54,
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed:
              () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => LoginScreen(apiService: apiService),
                ),
                (Route<dynamic> route) => false,
              ),
        ),
      ),
    );
  }

  Widget _buildManualCaptureButton() {
    return Positioned(
      bottom: 80,
      right: 20,
      child: FloatingActionButton(
        onPressed: _manualCaptureForWindows,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 8,
        child: const Icon(Icons.camera, size: 28),
        tooltip: 'Take Photo',
      ),
    );
  }

  Widget _buildCaptureInstructions() {
    return Positioned(
      bottom: 160,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Click to take photo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Helper method to open Windows location settings
  Future<void> _openWindowsLocationSettings() async {
    try {
      // Try to open Windows location settings
      final result = await Process.run('cmd', [
        '/c',
        'start',
        'ms-settings:privacy-location',
      ]);
      if (result.exitCode != 0) {
        throw Exception('Failed to open settings');
      }
    } catch (e) {
      // Fallback: show detailed instructions
      setState(() {
        _statusMessage =
            'Please manually go to: Windows Settings > Privacy & Security > Location > Location Services (ON)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width > 800;
    final isTablet = screenSize.width > 600 && !isDesktop;

    if (!_isCameraInitialized || !_cameraController.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                'Initializing camera...',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized)
            Positioned.fill(
              child: CameraPreview(
                _cameraController,
                key: ValueKey<bool>(_showPreview),
              ),
            ),

          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                ],
                stops: const [0.0, 0.2, 0.8, 1.0],
              ),
            ),
          ),

          // Preview Overlay
          if (_showPreview && _capturedImagePath != null)
            _buildPreviewOverlay(isDesktop, isTablet),

          // Main Content
          Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.only(
                  top: isDesktop ? 40 : 20,
                  left: isDesktop ? 40 : 20,
                  right: isDesktop ? 40 : 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed:
                          () => Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) =>
                                      LoginScreen(apiService: apiService),
                            ),
                            (Route<dynamic> route) => false,
                          ),
                      tooltip: 'Back',
                    ),
                    if (isDesktop)
                      Text(
                        'Attendance Capture',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(width: 48), // Balance the header
                  ],
                ),
              ),

              // Status Message
              if (!_showPreview)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 100 : 20,
                    vertical: 20,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _statusMessage,
                      key: ValueKey<String>(_statusMessage),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        shadows: [
                          const Shadow(
                            blurRadius: 10.0,
                            color: Colors.black,
                            offset: Offset(2.0, 2.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Spacer to push controls to bottom
              const Spacer(),

              // Controls Section
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 100 : 20,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_showPreview && _showRetryButton)
                      Column(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              _retryCount = 0;
                              _getCurrentLocation();
                            },
                            child: const Text('Retry Location'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[700],
                              padding: EdgeInsets.symmetric(
                                horizontal: isDesktop ? 32 : 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _openWindowsLocationSettings,
                            child: const Text('Open Location Settings'),
                          ),
                        ],
                      ),

                    // Capture Button (for Windows when needed)
                    if (!_showPreview &&
                        _isCameraInitialized &&
                        _cameraController.value.isInitialized &&
                        !_cameraController.supportsImageStreaming())
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: FloatingActionButton.extended(
                          onPressed: _manualCaptureForWindows,
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                          elevation: 8,
                          icon: const Icon(Icons.camera),
                          label: const Text('CAPTURE'),
                          tooltip: 'Take Photo',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewOverlay(bool isDesktop, bool isTablet) {
    return Container(
      color: Colors.black.withOpacity(0.95),
      child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(
              top: isDesktop ? 60 : 40,
              left: 40,
              right: 40,
            ),
            child: Column(
              children: [
                Text(
                  'REVIEW YOUR PHOTO',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Review your photo and click ACCEPT to continue with attendance',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Image Preview
          Expanded(
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth:
                      isDesktop
                          ? 800
                          : isTablet
                          ? 600
                          : MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 1,
                  maxScale: 3,
                  child: Image.file(File(_capturedImagePath!)),
                ),
              ),
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Reject Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 32 : 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _handlePreviewReject,
                ),

                const SizedBox(width: 20),

                // Accept Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('ACCEPT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 32 : 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _handlePreviewAccept,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
