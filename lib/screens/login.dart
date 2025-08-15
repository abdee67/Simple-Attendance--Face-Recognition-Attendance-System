import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '/screens/attendance_screen.dart';
import 'package:sqflite/sqflite.dart';
import '/db/dbmethods.dart';
import '/services/api_service.dart';
import '/db/dbHelper.dart';

class LoginScreen extends StatefulWidget {
  final ApiService apiService;
  const LoginScreen({required this.apiService, super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final DatabaseHelper db = DatabaseHelper.instance;
  final AttendancedbMethods dbmethods = AttendancedbMethods.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutQuart),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      // 1. Check connectivity with timeout
      bool isOnline;
      try {
        final connectivityResult = await Connectivity()
            .checkConnectivity()
            .timeout(const Duration(seconds: 3));
        isOnline = connectivityResult != ConnectivityResult.none;
      } catch (e) {
        isOnline = false;
        debugPrint('Connectivity check failed, assuming offline: $e');
      }

      // 2. Check if user exists in local DB
      final userExists = await dbmethods.checkUserExists(username);

      if (!isOnline) {
        // OFFLINE FLOW
        if (!userExists) {
          _showError('First login requires internet connection');
          return;
        }

        // Validate against local database
        final isValid = await dbmethods.validateUser(username, password);
        if (isValid) {
          _navigateToHome();
        } else {
          _showError(
            'Invalid credentials - please connect to internet to verify',
          );
        }
        return;
      }

      // ONLINE FLOW
      try {
        final apiResult = await widget.apiService
            .authenticateUser(username, password)
            .timeout(const Duration(seconds: 10));

        if (apiResult['success'] == true) {
          // Handle successful API authentication
          final userId = apiResult['userId']?.toString() ?? username;

          if (userExists) {
            // Check if password needs updating
            final localPassword = await dbmethods.getUserPassword(username);
            if (localPassword != password) {
              await dbmethods.updatePassword(userId, password);
              _showSuccess('Credentials updated');
            }
          } else {
            // New user - save to local DB
            await dbmethods.insertUser(username, password, userId: userId);
            _showSuccess('Welcome! Account created');
          }

          // Sync location data if available
          if (apiResult['latitude'] != null && apiResult['longitude'] != null) {
            await _resetAndSyncAddresses(apiResult);
          }

          _navigateToHome();
        } else {
          // API authentication failed - try local fallback
          if (userExists) {
            final isValid = await dbmethods.validateUser(username, password);
            if (isValid) {
              _navigateToHome();
              return;
            }
          }
          _showError(apiResult['error']?.toString() ?? 'Authentication failed');
        }
      } catch (apiError) {
        // API call failed - try local fallback
        debugPrint('API error: $apiError');
        if (userExists) {
          final isValid = await dbmethods.validateUser(username, password);
          if (isValid) {
            _navigateToHome();
            return;
          }
        }
        _showError('Connection unstable - try again or use offline mode');
      }
    } catch (e) {
      _showError(_getErrorMessage(e));
      debugPrint('Login error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getErrorMessage(dynamic error) {
    return error.toString().replaceFirst(
      'Null check operator used on a null value',
      'System error',
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _resetAndSyncAddresses(dynamic locationData) async {
    try {
      final database = await db.database;
      await database.delete('location');

      await database.insert('location', {
        'id': 1,
        'threshold':
            (locationData['threshold'] is String)
                ? double.tryParse(locationData['threshold']) ?? 0
                : locationData['threshold'],
        'latitude':
            (locationData['latitude'] is String)
                ? double.tryParse(locationData['latitude']) ?? 0
                : locationData['latitude'],
        'longitude':
            (locationData['longitude'] is String)
                ? double.tryParse(locationData['longitude']) ?? 0
                : locationData['longitude'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      _showError('Failed to reset and sync addresses: ${e.toString()}');
      rethrow;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.red.shade400,
      ),
    );
  }

  Future<void> _navigateToHome() async {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (context) => AttendanceScreen(userId: _usernameController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade900,
              Colors.blue.shade700,
              Colors.blue.shade500,
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: SlideTransition(position: _slideAnimation, child: child),
              );
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 500 : size.width * 0.9,
              ),
              child: Card(
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isDesktop ? 40.0 : 24.0),
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo and Title
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.2),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.person_outline,
                                  size: 48,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Savvy Attendance',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade900,
                                  fontSize: isDesktop ? 28 : 24,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Login To Your Account',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontSize: isDesktop ? 16 : 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Username Field
                          TextFormField(
                            controller: _usernameController,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                            ),
                            validator:
                                (value) => value!.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 20),

                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: Colors.grey.shade600,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator:
                                (value) => value!.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 8),

                          // Remember me + Forgot password (desktop only)
                          if (isDesktop)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: true,
                                        onChanged: (value) {},
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Text(
                                        'Remember me',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () {},
                                    child: Text(
                                      'Forgot password?',
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 24),

                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child:
                                _isLoading
                                    ? const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.blue,
                                            ),
                                      ),
                                    )
                                    : ElevatedButton(
                                      onPressed: _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade800,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        elevation: 4,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shadowColor: Colors.blue.shade300,
                                      ),
                                      child: Text(
                                        'Log iN',
                                        style: TextStyle(
                                          fontSize: isDesktop ? 16 : 14,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
