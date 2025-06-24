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

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final DatabaseHelper db = DatabaseHelper.instance;
  final AttendancedbMethods dbmethods = AttendancedbMethods.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut,
      ),
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
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult != ConnectivityResult.none;
    final username = _usernameController.text;
    final password = _passwordController.text;

    try {
      // Check if user exists in local DB
      final userExists = await dbmethods.checkUserExists(username);

      if (isOnline) {
        if (userExists) {
          // Online + existing user: validate locally
          final isValid = await dbmethods.validateUser(username, password);
          if (isValid) {
            _navigateToHome();
          } else {
            _showError('Invalid username or password!');
          }
        } else {
          // Online + new user: authenticate via API
          final result = await widget.apiService.authenticateUser(username, password);
          if (result['success'] == true) {
            // Save to local DB
            final userId = result['userId'] as String?;
            await dbmethods.insertUser(username, password, userId: userId);
            // RESET ADDRESS TABLE ONLY FOR FIRST-TIME LOGIN
            if (result['latitude'] != null && result['longitude'] != null) {
    await _resetAndSyncAddresses(result); // Pass the entire result
  }
            _navigateToHome();
          } else {
            _showError(result['error']);
          }
        }
      } else {
        if (userExists) {
          // Offline + existing user: validate locally
          final isValid = await dbmethods.validateUser(username, password);
          if (isValid) {
            _navigateToHome();
          } else {
            _showError('Invalid username or password!');
          }
        } else {
          // Offline + new user: not possible
          _showError('No internet connection. First login requires internet');
        }
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndSyncAddresses(dynamic locationData) async {
    try {
      final database = await db.database;
      await database.delete('location');
      
        await database.insert(
          'location',
         {
          'id': 1,
          'threshold': (locationData['threshold'] is String)
              ? double.tryParse(locationData['threshold']) ?? 0
              : locationData['threshold'],
          'latitude': (locationData['latitude'] is String)
              ? double.tryParse(locationData['latitude']) ?? 0
              : locationData['latitude'],
          'longitude': (locationData['longitude'] is String)
              ? double.tryParse(locationData['longitude']) ?? 0
              : locationData['longitude'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error resetting address table: $e');
      rethrow;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        backgroundColor: Colors.red.shade400,
      ),
    );
  }

  Future<void> _navigateToHome() async {
  if (!mounted) return;
  
  
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => AttendanceScreen(userId: _usernameController.text, )
       
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.shade800,
                Colors.blue.shade600,
                Colors.blue.shade400,
              ],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo and Title
                          Column(
                            children: [
                              const Icon(
                                Icons.account_circle,
                                size: 80,
                                color: Colors.blue,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Attendance Management',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sign in to continue',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey.shade600,
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
                              prefixIcon: const Icon(Icons.person),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),

                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            obscureText: _obscurePassword,
                            validator: (value) => value!.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 24),

                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade800,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 4,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text(
                                      'LOGIN',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 16),
/** 
                          // Forgot Password Link
                          TextButton(
                            onPressed: () {
                             // Open forgot password URL
                             // Make sure to add url_launcher to your pubspec.yaml and import it at the top
                             // import 'package:url_launcher/url_launcher.dart';
                             launchUrl(Uri.parse('https://demo.techequations.com/dover/signin.xhtml'), mode: LaunchMode.externalApplication);
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ),**/
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