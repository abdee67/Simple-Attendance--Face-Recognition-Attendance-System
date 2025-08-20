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
import 'package:simple_attendance/utils/face_painter.dart';

import 'package:tflite_flutter/tflite_flutter.dart';

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
  bool _isFaceDetected = false;
  bool _isCapturing = false;
  bool _isSubmitting = false;
  String? _capturedImagePath;
  String _statusMessage = 'Initializing camera...';
  int _retryCount = 0;
  final int _maxRetries = 3;
  bool _showRetryButton = false;
  Position? _currentPosition;
  final int _pendingSubmissions = 0;
  final db = AttendancedbMethods.instance;
  int _frameCount = 0;
  bool _isTorchOn = false;
  bool _showPreview = false;
  Rect? _detectedRect;
  late Interpreter _interpreter;

  // New state variables
  Timer? _captureTimer;
  int _captureAttempts = 0;
  static const int maxCaptureAttempts = 3;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  double _faceDetectionProgress = 0.0;
  final bool _showSuccess = false;
  bool _showError = false;
  bool isDetecting = false;
  // BlazeFace model parameters
  static const int INPUT_SIZE = 128; // Model input size
  static const double THRESHOLD = 0.7; // Confidence threshold
  static const int NUM_RESULTS = 6;
  static const String modelPath = 'assets/face_detection_front.tflite';
  late Float32List _inputBuffer;
  late List<List<List<double>>> _outputLocations;
  late List<List<double>> _outputScores;
  late final List<List<double>> _blazeFaceAnchors;
  StreamSubscription? _connectivitySubscription;
  final ApiService apiService = ApiService();
  // Max number of faces to detect

  @override
  void initState() {
    super.initState();
    _setupConnectivityListener();
    _blazeFaceAnchors = generateBlazeFaceAnchors();
    _loadModel().then((_) {
      // Pre-allocate based on model shape
      final inputShape = _interpreter.getInputTensor(0).shape;
      _inputBuffer = Float32List(inputShape[1] * inputShape[2] * inputShape[3]);

      final outputShape = _interpreter.getOutputTensor(0).shape;
      _outputLocations =
          (List.filled(
                outputShape[0] * outputShape[1] * outputShape[2],
                0.0,
              ).reshape(outputShape))
              .map<List<List<double>>>(
                (e) =>
                    (e as List<dynamic>)
                        .map<List<double>>(
                          (f) => (f as List<dynamic>).cast<double>(),
                        )
                        .toList(),
              )
              .toList();

      // Similarly for other outputs
    });
    _initializeCamera();
    // Setup animations
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _cameraController.dispose();
    _interpreter.close();
    _animationController.dispose();
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

  void _startCaptureTimer() {
    _captureTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isFaceDetected && _captureAttempts < maxCaptureAttempts) {
        _captureAttempts++;
        setState(
          () =>
              _statusMessage =
                  'Looking for face... Attempt $_captureAttempts/$maxCaptureAttempts',
        );
      } else if (_captureAttempts >= maxCaptureAttempts) {
        timer.cancel();
        _handleCaptureFailure();
      }
    });
  }

  void _handleCaptureFailure() {
    setState(() {
      _showError = true;
      _statusMessage = 'Face detection failed. Please try again.';
    });

    Future.delayed(const Duration(seconds: 3), () {
      setState(() => _showError = false);
      _resetCaptureProcess();
    });
  }

  void _resetCaptureProcess() {
    // Clear previous attempts
    _captureAttempts = 0;
    _faceDetectionProgress = 0.0;
    _isFaceDetected = false;

    // Clean up any existing files
    if (_capturedImagePath != null) {
      try {
        File(_capturedImagePath!).delete();
        _capturedImagePath = null;
      } catch (e) {
        if (kDebugMode) {}
      }
    }

    // Restart the process
    _startCaptureTimer();
    setState(() => _statusMessage = 'Align your face within the screen');
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            Platform.isAndroid
                ? ImageFormatGroup.yuv420
                : ImageFormatGroup.bgra8888,
      );

      await _cameraController.initialize();
      _cameraController.startImageStream(_processCameraImage);

      setState(() {
        _isCameraInitialized = true;
        _statusMessage = 'Align your face within the screen';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  // 1. First, update your model loading with proper verification
  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      _interpreter.allocateTensors();
      // Verify input/output tensors
      final inputTensor = _interpreter.getInputTensor(0);
      // Pre-allocate buffers based on model shape
      final inputShape = inputTensor.shape;
      _inputBuffer = Float32List(inputShape[1] * inputShape[2] * inputShape[3]);
    } catch (e) {
      setState(() => _statusMessage = 'Failed to load model: $e');
      throw Exception('Model loading failed: $e');
    }
  }

  // 2. Optimized tensor conversion
  Float32List _convertImageToTensor(CameraImage image) {
    // BlazeFace typically expects [1, 128, 128, 3] normalized to [-1,1]
    final inputSize = INPUT_SIZE;
    final input = Float32List(1 * inputSize * inputSize * 3);

    // Convert YUV to RGB and resize in one pass
    final yBuffer = image.planes[0].bytes;
    final uBuffer = image.planes[1].bytes;
    final vBuffer = image.planes[2].bytes;
    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final scaleX = image.width / inputSize;
    final scaleY = image.height / inputSize;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        // Map input coordinates to original image
        final srcX = (x * scaleX).toInt().clamp(0, image.width - 1);
        final srcY = (y * scaleY).toInt().clamp(0, image.height - 1);

        // Get YUV values
        final yValue = yBuffer[srcY * yRowStride + srcX];
        final uvIndex = (srcY ~/ 2) * uvRowStride + (srcX ~/ 2) * uvPixelStride;
        final uValue = uBuffer[uvIndex];
        final vValue = vBuffer[uvIndex];

        // Convert to RGB and normalize to [-1,1]
        final r = (yValue + 1.402 * (vValue - 128)) / 128.0 - 1.0;
        final g =
            (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)) /
                128.0 -
            1.0;
        final b = (yValue + 1.772 * (uValue - 128)) / 128.0 - 1.0;

        // Fill tensor (NHWC format)
        final index = (y * inputSize + x) * 3;
        input[index] = r;
        input[index + 1] = g;
        input[index + 2] = b;
      }
    }

    return input;
  }

  List<List<double>> generateBlazeFaceAnchors() {
    const List<int> strides = [8, 16];
    const List<int> anchorsPerStride = [2, 6];
    const double minScale = 0.1484375;
    const double maxScale = 0.75;
    const int inputSize = 128;

    List<List<double>> anchors = [];

    int layerId = 0;
    for (var stride in strides) {
      int featureMapSize = (inputSize / stride).floor();
      int numAnchors = anchorsPerStride[layerId];

      for (int y = 0; y < featureMapSize; y++) {
        for (int x = 0; x < featureMapSize; x++) {
          for (int a = 0; a < numAnchors; a++) {
            double xCenter = (x + 0.5) * stride / inputSize;
            double yCenter = (y + 0.5) * stride / inputSize;
            double scale =
                minScale + (maxScale - minScale) * a / (numAnchors - 1);
            anchors.add([xCenter, yCenter, scale, scale]);
          }
        }
      }

      layerId++;
    }

    return anchors;
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!_isCameraInitialized || _isCapturing) return;

    _frameCount++;
    if (_frameCount % 3 != 0) return;

    try {
      final input = _convertImageToTensor(image);
      final reshapedInput = input.reshape([1, INPUT_SIZE, INPUT_SIZE, 3]);

      var outputBoxes = List.generate(
        1,
        (_) => List.generate(896, (_) => List.filled(16, 0.0)),
      );
      var outputScores = List.generate(
        1,
        (_) => List.generate(896, (_) => List.filled(1, 0.0)),
      );
      final outputs = <int, Object>{0: outputBoxes, 1: outputScores};
      _interpreter.runForMultipleInputs([reshapedInput], outputs);

      List<List<double>> regressors = outputBoxes[0]; // [896][16]
      List<List<double>> scores = outputScores[0]; // [896][1]

      // Find best score above threshold
      int bestIndex = -1;
      double bestScore = 0.0;

      for (int i = 0; i < 896; i++) {
        final double confidence = 1 / (1 + exp(-scores[i][0]));
        if (confidence > bestScore && confidence > THRESHOLD) {
          bestScore = confidence;
          bestIndex = i;
        }
      }
      if (bestIndex == -1) {
        return;
      }

      // Decode bounding box
      final List<double> anchor = _blazeFaceAnchors[bestIndex];
      final List<double> reg = regressors[bestIndex];

      final double dx = reg[0];
      final double dy = reg[1];
      final double dw = reg[2];
      final double dh = reg[3];

      final double xCenter = anchor[0] + dx * anchor[2];
      final double yCenter = anchor[1] + dy * anchor[3];
      final double w = anchor[2] * exp(dw);
      final double h = anchor[3] * exp(dh);

      final double xMin = (xCenter - w / 2).clamp(0.0, 1.0);
      final double yMin = (yCenter - h / 2).clamp(0.0, 1.0);
      final double xMax = (xCenter + w / 2).clamp(0.0, 1.0);
      final double yMax = (yCenter + h / 2).clamp(0.0, 1.0);

      final faceRect = Rect.fromLTRB(xMin, yMin, xMax, yMax);
      _captureFace(faceRect);

      setState(() {
        _isFaceDetected = true;
        _detectedRect = faceRect;
      });
    } catch (e, stack) {
      setState(() {
        _statusMessage = 'Error processing image. Try again.$stack';
        _isFaceDetected = false;
      });
    }
  }

  Future<void> _captureFace(Rect faceBox) async {
    try {
      setState(() {
        _isCapturing = true;
        _statusMessage = 'Capturing face...';
      });

      await _cameraController.stopImageStream();
      await Future.delayed(const Duration(milliseconds: 300));

      final XFile picture = await _cameraController.takePicture();
      final bytes = await picture.readAsBytes();
      img.Image originalImage = img.decodeImage(bytes)!;

      if (_cameraController.description.lensDirection ==
          CameraLensDirection.front) {
        originalImage = img.flipHorizontal(originalImage);
      }

      final int imageWidth = originalImage.width;
      final int imageHeight = originalImage.height;

      // Convert normalized rect to absolute pixels with padding
      const double paddingFactor = 0.1;
      final double normLeft = (faceBox.left - paddingFactor).clamp(0.0, 1.0);
      final double normTop = (faceBox.top - paddingFactor).clamp(0.0, 1.0);
      final double normRight = (faceBox.right + paddingFactor).clamp(0.0, 1.0);
      final double normBottom = (faceBox.bottom + paddingFactor).clamp(
        0.0,
        1.0,
      );

      final int cropX = (normLeft * imageWidth).round();
      final int cropY = (normTop * imageHeight).round();
      final int cropWidth = ((normRight - normLeft) * imageWidth).round();
      final int cropHeight = ((normBottom - normTop) * imageHeight).round();

      final int clampedX = cropX.clamp(0, imageWidth - 1);
      final int clampedY = cropY.clamp(0, imageHeight - 1);
      final int clampedWidth = cropWidth.clamp(1, imageWidth - clampedX);
      final int clampedHeight = cropHeight.clamp(1, imageHeight - clampedY);
      final img.Image croppedFace = img.copyCrop(
        originalImage,
        x: clampedX,
        y: clampedY,
        width: clampedWidth,
        height: clampedHeight,
      );
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath =
          '${tempDir.path}/face_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File faceFile = File(filePath)
        ..writeAsBytesSync(img.encodeJpg(croppedFace, quality: 90));

      setState(() {
        _capturedImagePath = faceFile.path;
        _showPreview = true;
        _statusMessage = 'Face captured successfully';
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
      _statusMessage = 'Photo Accepted!...Finding location...';
    });
    if (Platform.isAndroid || Platform.isIOS) {
      _getCurrentLocation();
    } else {
      // For web or desktop, just submit attendance directly
      setState(() {
        _statusMessage =
            'Location not required on this platform. Submitting...';
      });
      _submitAttendance();
    }
  }

  void _handlePreviewReject() {
    setState(() {
      _showPreview = false;
      _statusMessage = 'Face capture rejected. Trying again...';
      _resetCaptureProcess();
    });

    // Delete the rejected image
    if (_capturedImagePath != null) {
      File(_capturedImagePath!).delete();
      _capturedImagePath = null;
    }
    // Restart the camera stream
    if (_isCameraInitialized && !_cameraController.value.isStreamingImages) {
      _cameraController.startImageStream(_processCameraImage);
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
        // Show message to user and wait for them to enable
        setState(
          () => _statusMessage = 'Please enable Location Services in Settings',
        );
        // Wait and check again in a loop
        for (int i = 0; i < 15; i++) {
          // Check for up to 15 seconds
          await Future.delayed(const Duration(seconds: 1));
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            setState(() => _statusMessage = 'Location Enabled! Lets go...');
            await Future.delayed(const Duration(seconds: 1));
            break;
          } else {
            setState(
              () =>
                  _statusMessage = 'Enable location... (${15 - i}s remaining)',
            );
          }
        }
      }
      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Guide user to app settings
        setState(
          () =>
              _statusMessage =
                  'Please enable location permissions in App Settings',
        );
        throw Exception('Location permissions permanently denied');
      }
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _currentPosition = position;
        _statusMessage = 'Location acquired! Submitting...';
      });

      await _submitAttendance();
    } catch (e) {
      setState(() => _statusMessage = 'Location error: ${e.toString()}');
      _showRetryButton = true;
    }
    ;
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

  Widget _buildTorchButton() {
    return Positioned(
      top: 50,
      right: 20,
      child: CircleAvatar(
        backgroundColor: Colors.black54,
        child: IconButton(
          icon: Icon(
            _isTorchOn ? Icons.flash_on : Icons.flash_off,
            color: Colors.white,
          ),
          onPressed: _toggleTorch,
        ),
      ),
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

  void _toggleTorch() async {
    if (_cameraController.value.flashMode == FlashMode.torch) {
      await _cameraController.setFlashMode(FlashMode.off);
      setState(() => _isTorchOn = false);
    } else {
      await _cameraController.setFlashMode(FlashMode.torch);
      setState(() => _isTorchOn = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check orientation for potential layout adjustments (e.g., in a complex layout)
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_isCameraInitialized)
            CameraPreview(_cameraController, key: ValueKey<bool>(_showPreview)),

          if (_isFaceDetected && _detectedRect != null)
            Positioned.fill(
              child: CustomPaint(
                painter: FacePainter(
                  rect: _detectedRect!,
                  imageSize: _cameraController.value.previewSize!,
                ),
              ),
            ),
          // Semi-transparent overlay
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

          // Preview overlay (on top of everything else when active)
          if (_showPreview && _capturedImagePath != null)
            _buildPreviewOverlay(),

          // Success overlay
          if (_showSuccess)
            Container(
              color: Colors.green.withOpacity(0.85),
              child: const Center(
                child: Icon(Icons.check_circle, size: 120, color: Colors.white),
              ),
            ),

          // Error overlay
          if (_showError)
            Container(
              color: Colors.red.withOpacity(0.85),
              child: const Center(
                child: Icon(
                  Icons.error_outline,
                  size: 120,
                  color: Colors.white,
                ),
              ),
            ),

          // Status message (always visible unless preview is showing)
          if (!_showPreview)
            Positioned(
              bottom: isPortrait ? 100 : 50, // Adjust based on orientation
              left: 20,
              right: 20,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _statusMessage,
                  key: ValueKey<String>(_statusMessage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isPortrait ? 18 : 16, // Responsive font size
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Attempt counter (only when not showing preview)
          if (!_showPreview)
            if (_captureAttempts >= maxCaptureAttempts &&
                !_isFaceDetected &&
                !_showPreview)
              Positioned(
                bottom: isPortrait ? 160 : 100, // Adjust based on orientation
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'We couldn\'t detect your face. Try better lighting.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 16),
                  ),
                ),
              ),

          // Manual retry button (only when error and not preview)
          if (_showError && !_showPreview)
            Positioned(
              bottom: isPortrait ? 40 : 20, // Adjust based on orientation
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('TRY AGAIN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () {
                    setState(() => _showError = false);
                    _captureAttempts = 0;
                    _faceDetectionProgress = 0.0;
                    _isFaceDetected = false;
                    _detectedRect = null;
                    _statusMessage = 'Align your face within the screen';
                    _resetCaptureProcess();
                    _startCaptureTimer();
                  },
                ),
              ),
            ),
          // Status message and retry button (always visible at the bottom, above control buttons)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_statusMessage, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (_showRetryButton)
                  ElevatedButton(
                    onPressed: () {
                      _retryCount = 0;
                      _getCurrentLocation();
                    },
                    child: const Text('Try Again'),
                  ),
              ],
            ),
          ),
          // Control buttons (always visible unless preview is showing)
          if (!_showPreview) ...[_buildBackButton(), _buildTorchButton()],
        ],
      ),
    );
  }

  Widget _buildPreviewOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Stack(
        children: [
          // Preview image
          Center(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Image.file(File(_capturedImagePath!)),
              ),
            ),
          ),
          // Accept/Reject buttons
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject button
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _handlePreviewReject,
                ),

                // Accept button
                ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('ACCEPT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _handlePreviewAccept,
                ),
              ],
            ),
          ),

          // Preview title
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'REVIEW YOUR PHOTO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize:
                      MediaQuery.of(context).size.width > 600
                          ? 28
                          : 22, // Responsive font size
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.black,
                      offset: const Offset(2.0, 2.0),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Preview instructions
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Make sure your face is clear and centered',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize:
                      MediaQuery.of(context).size.width > 600
                          ? 18
                          : 16, // Responsive font size
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.black,
                      offset: const Offset(2.0, 2.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Add this to your build method
        ],
      ),
    );
  }
}
