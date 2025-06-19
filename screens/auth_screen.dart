import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../utils/enums.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _nameController = TextEditingController();
  final _proteinTargetController = TextEditingController();
  final _calorieGoalController = TextEditingController();
  final _waterGoalController = TextEditingController();
  final _stepGoalController = TextEditingController();
  final _workoutGoalController = TextEditingController();
  final _sleepTargetController = TextEditingController();
  CalorieGoalType? _selectedCalorieGoalType;

  bool _isRegistering = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _proteinTargetController.dispose();
    _calorieGoalController.dispose();
    _waterGoalController.dispose();
    _stepGoalController.dispose();
    _workoutGoalController.dispose();
    _sleepTargetController.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MyApp()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found for that email.';
          break;
        case 'wrong-password':
          message = 'Wrong password provided.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        case 'user-disabled':
          message = 'This user account has been disabled.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check connection.';
          break;
        default:
          message = e.message ?? 'An unknown authentication error occurred.';
          break;
      }
      setState(() {
        _errorMessage = message;
      });
      _showSnackBar(message, isError: true);
      print('Firebase Auth Error (Sign-in): ${e.code} - ${e.message}');
    } catch (e) {
      final genericErrorMessage =
          'An unexpected error occurred: ${e.toString()}';
      setState(() {
        _errorMessage = genericErrorMessage;
      });
      _showSnackBar(genericErrorMessage, isError: true);
      print('Generic Error (Sign-in): $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _register() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (_selectedCalorieGoalType == null) {
      _showSnackBar('Please select a calorie goal type.', isError: true);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      UserCredential userCredential;
      final user = _auth.currentUser;

      if (user != null && user.isAnonymous) {
        // UPGRADE guest to registered!
        final credential =
            EmailAuthProvider.credential(email: email, password: password);
        userCredential = await user.linkWithCredential(credential);
      } else {
        // Standard registration
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final User? newUser = userCredential.user;
      if (newUser != null) {
        await _firestore.collection('users').doc(newUser.uid).set(
          {
            'name': _nameController.text.trim(),
            'email': newUser.email,
            'proteinTarget': int.tryParse(_proteinTargetController.text) ?? 0,
            'calorieGoal': int.tryParse(_calorieGoalController.text) ?? 0,
            'waterGoal': int.tryParse(_waterGoalController.text) ?? 0,
            'stepGoal': int.tryParse(_stepGoalController.text) ?? 0,
            'workoutGoal': int.tryParse(_workoutGoalController.text) ?? 0,
            'sleepTarget': double.tryParse(_sleepTargetController.text) ?? 0.0,
            'calorieGoalType':
                _selectedCalorieGoalType!.toString().split('.').last,
            'createdAt': FieldValue.serverTimestamp(),
            'isGuest': false,
          },
          SetOptions(merge: true),
        );
        _showSnackBar(
            'Registration and initial setup successful! Logging in...');
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MyApp()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The password provided is too weak.';
          break;
        case 'email-already-in-use':
          message = 'An account already exists for that email.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        case 'operation-not-allowed':
          message = 'Email/Password sign-in is not enabled in Firebase Auth.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check connection.';
          break;
        default:
          message = e.message ?? 'An unknown registration error occurred.';
          break;
      }
      setState(() {
        _errorMessage = message;
      });
      _showSnackBar(message, isError: true);
      print('Firebase Auth Error (Register): ${e.code} - ${e.message}');
    } catch (e) {
      final genericErrorMessage =
          'An unexpected error occurred: ${e.toString()}';
      setState(() {
        _errorMessage = genericErrorMessage;
      });
      _showSnackBar(genericErrorMessage, isError: true);
      print('Generic Error (Register): $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userCredential = await _auth.signInAnonymously();
      final user = userCredential.user;

      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'isGuest': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => MyApp()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = 'Guest login failed: ${e.message}';
      });
      _showSnackBar('Guest login failed: ${e.message}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Password Reset Logic
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Enter your email to reset password.', isError: true);
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showSnackBar('Password reset email sent!');
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found for that email.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        case 'network-request-failed':
          message = 'Network error. Check connection.';
          break;
        default:
          message = e.message ?? 'Failed to send reset email.';
          break;
      }
      _showSnackBar(message, isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegistering ? 'Register' : 'Login'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isRegistering
                    ? 'Create Your FitIndex Account'
                    : 'Welcome Back to FitIndex!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              if (_isRegistering) ...[
                _buildInputField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'John Doe',
                  icon: Icons.person,
                  keyboardType: TextInputType.name,
                ),
                const SizedBox(height: 15),
              ],
              _buildInputField(
                controller: _emailController,
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 15),
              _buildInputField(
                controller: _passwordController,
                label: 'Password',
                hint: 'Min 6 characters',
                icon: Icons.lock,
                isObscure: true,
              ),
              if (!_isRegistering)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(fontSize: 13),
                    ),
                    onPressed: _resetPassword,
                  ),
                ),
              const SizedBox(height: 15),
              if (_isRegistering) ...[
                const SizedBox(height: 20),
                Text(
                  'Set Your Initial Goals',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildInputField(
                  controller: _proteinTargetController,
                  label: 'Daily Protein Goal (grams)',
                  hint: 'e.g., 150',
                  icon: Icons.egg,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: _calorieGoalController,
                  label: 'Daily Calorie Goal (kcal)',
                  hint: 'e.g., 2000',
                  icon: Icons.local_fire_department,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                Text(
                  'Calorie Goal Type',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...CalorieGoalType.values.map((type) {
                  return RadioListTile<CalorieGoalType>(
                    title: Text(type.toString().split('.').last.toUpperCase()),
                    value: type,
                    groupValue: _selectedCalorieGoalType,
                    onChanged: (CalorieGoalType? value) {
                      setState(() {
                        _selectedCalorieGoalType = value;
                      });
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  );
                }).toList(),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: _waterGoalController,
                  label: 'Daily Water Goal (ml)',
                  hint: 'e.g., 3000',
                  icon: Icons.water_drop,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: _stepGoalController,
                  label: 'Daily Step Goal',
                  hint: 'e.g., 10000',
                  icon: Icons.directions_run,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: _workoutGoalController,
                  label: 'Weekly Workouts Goal (days)',
                  hint: 'e.g., 3',
                  icon: Icons.fitness_center_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  controller: _sleepTargetController,
                  label: 'Daily Sleep Goal (hours)',
                  hint: 'e.g., 7.5',
                  icon: Icons.bed,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 30),
              ],
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        ElevatedButton(
                          onPressed: _isRegistering ? _register : _signIn,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                          ),
                          child: Text(
                              _isRegistering ? 'Register Account' : 'Sign In',
                              style: const TextStyle(fontSize: 18)),
                        ),
                        const SizedBox(height: 10),
                        // --- Continue as Guest Button ---
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_outline),
                          label: const Text("Continue as Guest"),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: Colors.grey[600],
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _continueAsGuest,
                        ),
                        const SizedBox(height: 15),
                      ],
                    ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isRegistering = !_isRegistering;
                    _errorMessage = null;
                    _emailController.clear();
                    _passwordController.clear();
                    _nameController.clear();
                    _proteinTargetController.clear();
                    _calorieGoalController.clear();
                    _waterGoalController.clear();
                    _stepGoalController.clear();
                    _workoutGoalController.clear();
                    _sleepTargetController.clear();
                    _selectedCalorieGoalType = null;
                  });
                },
                child: Text(
                  _isRegistering
                      ? 'Already have an account? Sign In'
                      : 'Don\'t have an account? Register',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.secondary),
                ),
              ),
              const SizedBox(height: 40),
              const Column(
                children: [
                  Text(
                    'App version: 2.0.0',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    'Made by: Faris Alblooki',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    bool isObscure = false,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
      keyboardType: keyboardType,
      obscureText: isObscure,
    );
  }
}
