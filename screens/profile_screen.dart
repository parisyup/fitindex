import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/enums.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _friendFormKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _proteinTargetController = TextEditingController();
  final _calorieGoalController = TextEditingController();
  final _sleepTargetController = TextEditingController();
  final _stepGoalController = TextEditingController();
  final _waterGoalController = TextEditingController();
  final _friendEmailController = TextEditingController();

  CalorieGoalType? _selectedCalorieGoalType;
  bool _isLoading = false;
  String? _message;
  bool _isGuest = false;
  bool _keyboardVisible = false;

  String _userEmail = '';
  double? _globalRankScore; // --- Add this

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
    _fetchGlobalScore(); // --- Add this
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proteinTargetController.dispose();
    _calorieGoalController.dispose();
    _sleepTargetController.dispose();
    _stepGoalController.dispose();
    _waterGoalController.dispose();
    _friendEmailController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final value = WidgetsBinding.instance.window.viewInsets.bottom > 0;
    if (value != _keyboardVisible) {
      setState(() {
        _keyboardVisible = value;
      });
    }
    super.didChangeMetrics();
  }

  // --- Fetch current score from DB
  Future<void> _fetchGlobalScore() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _globalRankScore = null);
      return;
    }
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      double score =
          (userDoc.data()?['globalRankScore'] as num?)?.toDouble() ?? 0.0;
      setState(() => _globalRankScore = score);
    } catch (e) {
      setState(() => _globalRankScore = null);
    }
  }

  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Please log in to view your profile.', isError: true);
      return;
    }

    _userEmail = user.email ?? "";

    setState(() {
      _isLoading = true;
    });

    try {
      final docSnapshot =
          await _firestore.collection('users').doc(user.uid).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        _proteinTargetController.text =
            (data['proteinTarget'] ?? '').toString();
        _calorieGoalController.text = (data['calorieGoal'] ?? '').toString();
        _sleepTargetController.text = (data['sleepTarget'] ?? '').toString();
        _stepGoalController.text = (data['stepGoal'] ?? '').toString();
        _waterGoalController.text = (data['waterGoal'] ?? '').toString();

        final calorieGoalTypeString = data['calorieGoalType'] as String?;
        if (calorieGoalTypeString != null) {
          _selectedCalorieGoalType = CalorieGoalType.values.firstWhere(
            (e) => e.toString().split('.').last == calorieGoalTypeString,
            orElse: () => CalorieGoalType.maintenance,
          );
        }

        _isGuest =
            user.isAnonymous || (user.email == null || user.email!.isEmpty);
      } else {
        _showMessage('Welcome! Set your fitness goals to get started.',
            isError: false);
        _isGuest =
            user.isAnonymous || (user.email == null || user.email!.isEmpty);
      }
    } catch (e) {
      _showMessage('Error loading profile: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- RESET SCORE LOGIC ---
  Future<void> _showResetScoreDialog() async {
    if (_globalRankScore == null) {
      _showMessage('Error: Could not fetch your score.', isError: true);
      return;
    }
    if (_globalRankScore! <= 0) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Reset Score'),
          content: const Text(
              'You need to have a score above 0 to reset it. Earn some points, then try again!'),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
      return;
    }

    final confirmController = TextEditingController();
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Your Score'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'This will set your global score to 0. To confirm, type RESET below.'),
            const SizedBox(height: 14),
            TextField(
              controller: confirmController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Type RESET to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset Score'),
            onPressed: () {
              if (confirmController.text.trim() == 'RESET') {
                confirmed = true;
                Navigator.of(ctx).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please type RESET to confirm.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );

    if (!confirmed) return;

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('Not logged in.');
      setState(() => _isLoading = true);

      // --- Actually reset score in DB ---
      await _firestore.collection('users').doc(user.uid).set(
        {'globalRankScore': 0.0},
        SetOptions(merge: true),
      );
      await _fetchGlobalScore();
      _showMessage('Score reset to 0!');
    } catch (e) {
      _showMessage('Error resetting score: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }
  // --- END RESET SCORE LOGIC ---

  Future<void> _saveUserProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Please log in to save your profile.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'proteinTarget': int.tryParse(_proteinTargetController.text) ?? 0,
          'calorieGoal': int.tryParse(_calorieGoalController.text) ?? 0,
          'sleepTarget': double.tryParse(_sleepTargetController.text) ?? 0.0,
          'stepGoal': int.tryParse(_stepGoalController.text) ?? 0,
          'waterGoal': int.tryParse(_waterGoalController.text) ?? 0,
          'calorieGoalType':
              _selectedCalorieGoalType?.toString().split('.').last,
          'lastUpdated': FieldValue.serverTimestamp(),
          'email': user.email,
        },
        SetOptions(merge: true),
      );
      _showMessage('Profile updated successfully!');
    } catch (e) {
      _showMessage('Error saving profile: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addFriendByEmail() async {
    if (!_friendFormKey.currentState!.validate()) {
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showMessage('You must be logged in to add friends.', isError: true);
      return;
    }

    final friendEmail = _friendEmailController.text.trim();

    if (friendEmail == currentUser.email) {
      _showMessage('You cannot add yourself as a friend.', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: friendEmail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        _showMessage('No user found with that email.', isError: true);
        return;
      }

      final friendUid = querySnapshot.docs.first.id;

      await _firestore.collection('users').doc(currentUser.uid).set({
        'friends': FieldValue.arrayUnion([friendUid]),
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(friendUid).set({
        'friends': FieldValue.arrayUnion([currentUser.uid]),
      }, SetOptions(merge: true));

      _showMessage('Friend added successfully!');
      _friendEmailController.clear();
    } catch (e) {
      _showMessage('Error adding friend: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      _showMessage('Error logging out: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Not logged in.', isError: true);
      return;
    }

    TextEditingController confirmController = TextEditingController();
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Type DELETE below to permanently delete your account. This cannot be undone.'),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Type DELETE to confirm',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
              onPressed: () {
                if (confirmController.text.trim() == 'DELETE') {
                  confirmed = true;
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please type DELETE to confirm.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );

    if (!confirmed) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Delete Firestore user data
      await _firestore.collection('users').doc(user.uid).delete();

      // Delete Firebase Auth user
      await user.delete();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthScreen()),
          (Route<dynamic> route) => false,
        );
      }
      _showMessage('Account deleted.', isError: false);
    } catch (e) {
      _showMessage('Error deleting account: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
    setState(() {
      _message = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile & Goals'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Personal Goals Form ---
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Text(
                              'Set Your Daily Fitness Goals',
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            _buildTextFormField(
                              _stepGoalController,
                              'Daily Step Goal',
                              'e.g., 10000',
                              TextInputType.number,
                            ),
                            _buildTextFormField(
                              _waterGoalController,
                              'Daily Water Goal (ml)',
                              'e.g., 3000',
                              TextInputType.number,
                            ),
                            _buildTextFormField(
                              _proteinTargetController,
                              'Daily Protein Target (grams)',
                              'e.g., 120',
                              TextInputType.number,
                            ),
                            _buildTextFormField(
                              _sleepTargetController,
                              'Daily Sleep Target (hours)',
                              'e.g., 7.5',
                              TextInputType.numberWithOptions(decimal: true),
                            ),
                            _buildTextFormField(
                              _calorieGoalController,
                              'Daily Calorie Goal',
                              'e.g., 2000',
                              TextInputType.number,
                            ),
                            _buildDropdownField(),
                            const SizedBox(height: 30),
                            ElevatedButton(
                              onPressed: _saveUserProfile,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Save Goals',
                                  style: TextStyle(fontSize: 18)),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 50, thickness: 1),

                      // --- Add Friend Section (unchanged) ---
                      _isGuest
                          ? Column(
                              children: [
                                const Icon(Icons.lock_outline,
                                    size: 40, color: Colors.grey),
                                const SizedBox(height: 10),
                                const Text(
                                  "Register to add friends and unlock social features.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const AuthScreen()),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 50),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.secondary,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onSecondary,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Register to Add Friends',
                                      style: TextStyle(fontSize: 18)),
                                ),
                              ],
                            )
                          : Form(
                              key: _friendFormKey,
                              child: Column(
                                children: [
                                  if (_userEmail.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.email,
                                              size: 18, color: Colors.grey),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Your Email: $_userEmail',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Text(
                                    'Add a Friend',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  _buildTextFormField(
                                    _friendEmailController,
                                    'Friend\'s Email',
                                    'friend@example.com',
                                    TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter an email';
                                      }
                                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                          .hasMatch(value)) {
                                        return 'Enter a valid email address';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  ElevatedButton(
                                    onPressed: _addFriendByEmail,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize:
                                          const Size(double.infinity, 50),
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Add Friend',
                                        style: TextStyle(fontSize: 18)),
                                  ),
                                ],
                              ),
                            ),
                      const Divider(height: 50, thickness: 1),

                      // --- RESET SCORE BUTTON ---
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _showResetScoreDialog,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text(
                          'Reset Score',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // --- Logout Button ---
                      ElevatedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout',
                            style: TextStyle(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor:
                              Theme.of(context).colorScheme.onError,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      // --- Delete Account Button ---
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _deleteAccount,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text(
                          'Delete Account',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
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
                      const SizedBox(height: 80), // for button spacing
                    ],
                  ),
                ),
                // Hide Keyboard FAB
                if (_keyboardVisible)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: FloatingActionButton.extended(
                      icon: const Icon(Icons.keyboard_hide),
                      label: const Text("Hide Keyboard"),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildTextFormField(
    TextEditingController controller,
    String label,
    String hint,
    TextInputType keyboardType, {
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        keyboardType: keyboardType,
        validator: validator ??
            (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a value';
              }
              if (keyboardType == TextInputType.number ||
                  keyboardType ==
                      TextInputType.numberWithOptions(decimal: true)) {
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
              }
              return null;
            },
      ),
    );
  }

  Widget _buildDropdownField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<CalorieGoalType>(
        value: _selectedCalorieGoalType,
        decoration: InputDecoration(
          labelText: 'Calorie Goal Type',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        items: CalorieGoalType.values.map((type) {
          return DropdownMenuItem(
            value: type,
            child: Text(type.toString().split('.').last.toUpperCase()),
          );
        }).toList(),
        onChanged: (newValue) {
          setState(() {
            _selectedCalorieGoalType = newValue;
          });
        },
        validator: (value) {
          if (value == null) {
            return 'Please select a calorie goal type';
          }
          return null;
        },
      ),
    );
  }
}
