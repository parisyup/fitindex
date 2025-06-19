import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/enums.dart';

// Enum to represent calorie goal types

class TargetsSetupScreen extends StatefulWidget {
  const TargetsSetupScreen({super.key});

  @override
  State<TargetsSetupScreen> createState() => _TargetsSetupScreenState();
}

class _TargetsSetupScreenState extends State<TargetsSetupScreen> {
  // Text controllers for input fields
  final _proteinTargetController = TextEditingController();
  final _calorieGoalController = TextEditingController(); // New: Calorie goal
  final _waterGoalController = TextEditingController(); // New: Water goal
  final _stepGoalController = TextEditingController(); // New: Step goal
  final _workoutGoalController = TextEditingController(); // New: Workout goal

  CalorieGoalType? _selectedCalorieGoalType; // For deficit/maintenance/surplus
  bool _isLoading = false;
  String? _message; // To display success or error messages

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadTargets(); // Load existing targets when the screen initializes
  }

  @override
  void dispose() {
    _proteinTargetController.dispose();
    _calorieGoalController.dispose();
    _waterGoalController.dispose();
    _stepGoalController.dispose();
    _workoutGoalController.dispose();
    super.dispose();
  }

  // Helper to show SnackBar messages
  void _showMessage(String msg, {bool isError = false}) {
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

  // Load existing targets from Firestore
  Future<void> _loadTargets() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Please log in to set targets.', isError: true);
      setState(() {
        // Ensure isLoading is false if user is null
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          _proteinTargetController.text =
              (data['proteinTarget'] ?? '').toString();
          _calorieGoalController.text =
              (data['calorieGoal'] ?? '').toString(); // Load calorie goal
          _waterGoalController.text =
              (data['waterGoal'] ?? '').toString(); // Load water goal
          _stepGoalController.text =
              (data['stepGoal'] ?? '').toString(); // Load step goal
          _workoutGoalController.text =
              (data['workoutGoal'] ?? '').toString(); // Load workout goal

          final String? calorieGoalTypeString = data['calorieGoalType'];
          if (calorieGoalTypeString != null) {
            _selectedCalorieGoalType = CalorieGoalType.values.firstWhere(
              (e) => e.toString().split('.').last == calorieGoalTypeString,
              orElse: () => CalorieGoalType.maintenance, // Default if not found
            );
          }
          _showMessage('Targets loaded successfully!');
        }
      } else {
        _showMessage('No targets set yet. Please enter your goals.',
            isError: false);
      }
    } catch (e) {
      _showMessage('Error loading targets: ${e.toString()}', isError: true);
      print('DEBUG: Error loading targets: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Save targets to Firestore
  Future<void> _saveTargets() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Please log in to save targets.', isError: true);
      return;
    }
    if (_selectedCalorieGoalType == null) {
      _showMessage('Please select a calorie goal type.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'proteinTarget': int.tryParse(_proteinTargetController.text) ?? 0,
          'calorieGoal': int.tryParse(_calorieGoalController.text) ??
              0, // Save calorie goal
          'waterGoal':
              int.tryParse(_waterGoalController.text) ?? 0, // Save water goal
          'stepGoal':
              int.tryParse(_stepGoalController.text) ?? 0, // Save step goal
          'workoutGoal': int.tryParse(_workoutGoalController.text) ??
              0, // Save workout goal
          'calorieGoalType': _selectedCalorieGoalType!
              .toString()
              .split('.')
              .last, // Save enum name as string
          'lastUpdatedTargets':
              FieldValue.serverTimestamp(), // Timestamp for last update
        },
        SetOptions(
            merge: true), // Merge with existing user data to avoid overwriting
      );
      _showMessage('Targets saved successfully!');
    } catch (e) {
      _showMessage('Error saving targets: ${e.toString()}', isError: true);
      print('DEBUG: Error saving targets: $e');
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
        title: const Text('Set Your Targets'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Personalized Goals',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Protein Target Input
                  _buildInputField(
                    controller: _proteinTargetController,
                    label: 'Daily Protein Target (grams)',
                    hint: 'e.g., 150',
                    icon: Icons.egg,
                  ),
                  const SizedBox(height: 15),

                  // Calorie Goal Input
                  _buildInputField(
                    controller: _calorieGoalController,
                    label: 'Daily Calorie Goal (kcal)',
                    hint: 'e.g., 2000',
                    icon: Icons.local_fire_department,
                  ),
                  const SizedBox(height: 15),

                  // Calorie Goal Type Radio Buttons
                  Text(
                    'Calorie Goal Type',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ...CalorieGoalType.values.map((type) {
                    return RadioListTile<CalorieGoalType>(
                      title:
                          Text(type.toString().split('.').last.toUpperCase()),
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

                  // Water Goal Input
                  _buildInputField(
                    controller: _waterGoalController,
                    label: 'Daily Water Goal (ml)',
                    hint: 'e.g., 3000',
                    icon: Icons.water_drop,
                  ),
                  const SizedBox(height: 15),

                  // Step Goal Input
                  _buildInputField(
                    controller: _stepGoalController,
                    label: 'Daily Step Goal',
                    hint: 'e.g., 10000',
                    icon: Icons.directions_run,
                  ),
                  const SizedBox(height: 15),

                  // Workout Goal Input
                  _buildInputField(
                    controller: _workoutGoalController,
                    label: 'Weekly Workouts Goal (days)',
                    hint: 'e.g., 3',
                    icon: Icons.fitness_center_outlined,
                  ),
                  const SizedBox(height: 30),

                  // Save Button
                  ElevatedButton(
                    onPressed: _saveTargets,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      'Save Targets',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 15),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // Helper widget for consistent input field styling
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
      keyboardType: TextInputType.number,
    );
  }
}
