import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fit_index/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InputForTodayScreen extends StatefulWidget {
  const InputForTodayScreen({super.key});

  @override
  State<InputForTodayScreen> createState() => _InputForTodayScreenState();
}

class _ScoreResults {
  final double finalScore;
  final double percentScore;

  _ScoreResults({required this.finalScore, required this.percentScore});
}

class _InputForTodayScreenState extends State<InputForTodayScreen>
    with WidgetsBindingObserver {
  final _stepsController = TextEditingController();
  final _caloriesConsumedController = TextEditingController();
  final _sleepHoursController = TextEditingController();
  final _proteinGramsController = TextEditingController();
  final _waterIntakeController = TextEditingController();
  final _weightController = TextEditingController();

  bool _didntTrackSteps = false;
  bool _didntTrackCalories = false;
  bool _didntTrackProtein = false;
  bool _didntTrackWater = false;

  bool _workoutsCompleted = false;
  bool _supplementsTaken = false;
  bool _isLoading = false;
  String? _message;

  double? _lastCalculatedDailyScore;
  double? _lastCalculatedPercent;

  int _mood = 3;

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _userTargets;

  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDailyDataAndTargets();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepsController.dispose();
    _caloriesConsumedController.dispose();
    _sleepHoursController.dispose();
    _proteinGramsController.dispose();
    _waterIntakeController.dispose();
    _weightController.dispose();
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

  String _getDateId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _lastCalculatedDailyScore = null;
        _lastCalculatedPercent = null;
      });
      _loadDailyDataAndTargets();
    }
  }

  Future<void> _loadDailyDataAndTargets() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Please log in to load data.', isError: true);
      setState(() {
        _isLoading = false;
        _lastCalculatedDailyScore = null;
        _lastCalculatedPercent = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
      _lastCalculatedDailyScore = null;
      _lastCalculatedPercent = null;
    });

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        _userTargets = userDoc.data();
      } else {
        _userTargets = {};
        _showMessage(
          'User targets not set. Please update your profile to set goals!',
          isError: true,
        );
      }

      final docId = _getDateId(_selectedDate);
      final docRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('daily_logs')
          .doc(docId);

      final docSnapshot = await docRef.get().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Firestore fetch timed out after 10 seconds.');
        },
      );

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        _stepsController.text = (data['stepsPerDay'] ?? '').toString();
        _workoutsCompleted = data['workoutsCompleted'] ?? false;
        _caloriesConsumedController.text =
            (data['caloriesConsumed'] ?? '').toString();
        _sleepHoursController.text = (data['sleepHours'] ?? '').toString();
        _proteinGramsController.text = (data['proteinGrams'] ?? '').toString();
        _supplementsTaken = data['supplementsTaken'] ?? false;
        _waterIntakeController.text = (data['waterIntake'] ?? '').toString();
        _weightController.text = (data['weight'] ?? '').toString();
        _mood = (data['mood'] ?? _mood) as int;

        _didntTrackSteps = data['didntTrackSteps'] ?? false;
        _didntTrackCalories = data['didntTrackCalories'] ?? false;
        _didntTrackProtein = data['didntTrackProtein'] ?? false;
        _didntTrackWater = data['didntTrackWater'] ?? false;

        if (data.containsKey('dailyScore')) {
          _lastCalculatedDailyScore = (data['dailyScore'] as num).toDouble();
        } else {
          _lastCalculatedDailyScore = null;
        }
        if (data.containsKey('percentScore')) {
          _lastCalculatedPercent = (data['percentScore'] as num).toDouble();
        } else {
          _lastCalculatedPercent = null;
        }
      } else {
        _stepsController.clear();
        _caloriesConsumedController.clear();
        _sleepHoursController.clear();
        _proteinGramsController.clear();
        _waterIntakeController.clear();
        _weightController.clear();
        _workoutsCompleted = false;
        _supplementsTaken = false;
        _mood = 3;
        _lastCalculatedDailyScore = null;
        _lastCalculatedPercent = null;
        _didntTrackSteps = false;
        _didntTrackCalories = false;
        _didntTrackProtein = false;
        _didntTrackWater = false;
        _showMessage(
          'No data logged for ${_getDateId(_selectedDate)} yet. Start inputting!',
          isError: false,
        );
      }
    } catch (e) {
      print('DEBUG: Error in _loadDailyDataAndTargets: $e');
      _showMessage('Error loading data: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDailyData() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showMessage('Please log in to save data.', isError: true);
      return;
    }
    if (_userTargets == null || _userTargets!.isEmpty) {
      _showMessage(
        'Cannot calculate score. Please set your targets in your profile first.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final docId = _getDateId(_selectedDate);
      final _ScoreResults results = _calculateDailyScore();

      final userDocRef = _firestore.collection('users').doc(user.uid);
      final userDocSnapshot = await userDocRef.get();
      Map<String, dynamic> userData = userDocSnapshot.data() ?? {};
      double currentGlobalRankScore =
          (userData['globalRankScore'] as num?)?.toDouble() ?? 0.0;

      final dailyLogDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('daily_logs')
          .doc(docId)
          .get();
      double previousDailyScore = 0.0;
      if (dailyLogDoc.exists && dailyLogDoc.data()!.containsKey('dailyScore')) {
        previousDailyScore =
            (dailyLogDoc.data()!['dailyScore'] as num).toDouble();
      }

      double newGlobalRankScore =
          currentGlobalRankScore - previousDailyScore + results.finalScore;

      await userDocRef.set({
        'globalRankScore': newGlobalRankScore,
        'lastUpdatedRank': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('daily_logs')
          .doc(docId)
          .set({
        'stepsPerDay': int.tryParse(_stepsController.text) ?? 0,
        'workoutsCompleted': _workoutsCompleted,
        'caloriesConsumed': int.tryParse(_caloriesConsumedController.text) ?? 0,
        'sleepHours': double.tryParse(_sleepHoursController.text) ?? 0.0,
        'proteinGrams': int.tryParse(_proteinGramsController.text) ?? 0,
        'supplementsTaken': _supplementsTaken,
        'waterIntake': int.tryParse(_waterIntakeController.text) ?? 0,
        'weight': double.tryParse(_weightController.text) ?? 0.0,
        'mood': _mood,
        'timestamp': FieldValue.serverTimestamp(),
        'dailyScore': results.finalScore,
        'percentScore': results.percentScore,
        'didntTrackSteps': _didntTrackSteps,
        'didntTrackCalories': _didntTrackCalories,
        'didntTrackProtein': _didntTrackProtein,
        'didntTrackWater': _didntTrackWater,
      }, SetOptions(merge: true));

      setState(() {
        _lastCalculatedDailyScore = results.finalScore;
        _lastCalculatedPercent = results.percentScore;
      });
      _showMessage(
          'Data saved and rank updated for ${_getDateId(_selectedDate)}!');
    } catch (e) {
      _showMessage('Error saving data: ${e.toString()}', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  _ScoreResults _calculateDailyScore() {
    if (_userTargets == null || _userTargets!.isEmpty) {
      print(
          'DEBUG: User targets are not loaded or are empty. Cannot calculate score.');
      return _ScoreResults(finalScore: 0.0, percentScore: 0.0);
    }

    // Check if truly nothing is tracked (all blank, all toggles false, no workouts/supps)
    final allEmpty = (_stepsController.text.trim().isEmpty &&
            !_didntTrackSteps) &&
        (_caloriesConsumedController.text.trim().isEmpty &&
            !_didntTrackCalories) &&
        (_proteinGramsController.text.trim().isEmpty && !_didntTrackProtein) &&
        (_waterIntakeController.text.trim().isEmpty && !_didntTrackWater) &&
        _sleepHoursController.text.trim().isEmpty &&
        !_workoutsCompleted &&
        !_supplementsTaken;

    if (allEmpty) {
      return _ScoreResults(finalScore: -25.0, percentScore: 0.0);
    }

    List<double> metricScores = [];
    int metricCount = 0;

    // Steps
    final stepsGoal = (_userTargets!['stepGoal'] ?? 0).toDouble();
    double? stepsActual = _stepsController.text.isEmpty
        ? null
        : double.tryParse(_stepsController.text);
    if (stepsGoal > 0) {
      metricScores
          .add(_getRawMetricScore(stepsActual, stepsGoal, _didntTrackSteps));
      metricCount++;
    }

    // Calories
    final calorieGoal = (_userTargets!['calorieGoal'] ?? 0).toDouble();
    final calorieGoalTypeString =
        _userTargets!['calorieGoalType'] ?? 'maintenance';
    final CalorieGoalType calorieGoalType = CalorieGoalType.values.firstWhere(
      (e) => e.toString().split('.').last == calorieGoalTypeString,
      orElse: () => CalorieGoalType.maintenance,
    );
    double? caloriesActual = _caloriesConsumedController.text.isEmpty
        ? null
        : double.tryParse(_caloriesConsumedController.text);
    if (calorieGoal > 0) {
      metricScores.add(_getRawCaloriesScore(
          caloriesActual, calorieGoal, calorieGoalType, _didntTrackCalories));
      metricCount++;
    }

    // Protein
    final proteinTarget = (_userTargets!['proteinTarget'] ?? 0).toDouble();
    double? proteinActual = _proteinGramsController.text.isEmpty
        ? null
        : double.tryParse(_proteinGramsController.text);
    if (proteinTarget > 0) {
      metricScores.add(
          _getRawMetricScore(proteinActual, proteinTarget, _didntTrackProtein));
      metricCount++;
    }

    // Water
    final waterGoal = (_userTargets!['waterGoal'] ?? 0).toDouble();
    double? waterActual = _waterIntakeController.text.isEmpty
        ? null
        : double.tryParse(_waterIntakeController.text);
    if (waterGoal > 0) {
      metricScores
          .add(_getRawMetricScore(waterActual, waterGoal, _didntTrackWater));
      metricCount++;
    }

    // Sleep (no didn't track)
    final sleepTarget = (_userTargets!['sleepTarget'] ?? 8.0).toDouble();
    double? sleepActual = _sleepHoursController.text.isEmpty
        ? null
        : double.tryParse(_sleepHoursController.text);
    if (sleepTarget > 0) {
      double sleepScore = 0.0;
      if (sleepActual != null) {
        double deviation = (sleepActual - sleepTarget).abs();
        double adherencePercentage;
        if (deviation <= 0.5) {
          adherencePercentage = 1.0;
        } else {
          double maxDeviationConsidered = 2.0;
          adherencePercentage = 1.0 - (deviation / maxDeviationConsidered);
          if (adherencePercentage < 0) adherencePercentage = 0;
        }
        sleepScore = (adherencePercentage * 100.0).clamp(0, 100);
      }
      metricScores.add(sleepScore);
      metricCount++;
    }

    // Workouts
    metricScores.add(_workoutsCompleted ? 100.0 : 0.0);
    metricCount++;
    // Supplements
    metricScores.add(_supplementsTaken ? 100.0 : 0.0);
    metricCount++;

    double avgPercent = metricScores.isNotEmpty
        ? metricScores.reduce((a, b) => a + b) / metricScores.length
        : 0.0;

    double finalScore;
    if (avgPercent < 50) {
      finalScore = -15.0 + ((avgPercent / 50.0) * 15.0); // -15 to 0
    } else if (avgPercent < 70) {
      finalScore = ((avgPercent - 50.0) / 20.0) * 39.0; // 0 to 39
    } else if (avgPercent < 90) {
      finalScore = 39.0 + ((avgPercent - 70.0) / 20.0) * 40.0; // 39 to 79
    } else {
      finalScore = 79.0 + ((avgPercent - 90.0) / 10.0) * 21.0; // 79 to 100
      if (finalScore > 100) finalScore = 100.0;
    }

    // Minimum is -15 if any metric is tracked
    if (finalScore < -15.0) finalScore = -15.0;

    return _ScoreResults(
      finalScore: finalScore,
      percentScore: avgPercent.clamp(0, 100),
    );
  }

  double _getRawMetricScore(double? actual, double target, bool didntTrack) {
    if (target <= 0) return 0.0;
    if (didntTrack) return 25.0;
    if (actual == null || actual.isNaN) return 0.0;
    double pct = (actual / target).clamp(0.0, 1.0);
    return pct * 100.0;
  }

  double _getRawCaloriesScore(double? actual, double target,
      CalorieGoalType goalType, bool didntTrack) {
    if (target <= 0) return 0.0;
    if (didntTrack) return 25.0;
    if (actual == null || actual.isNaN) return 0.0;
    double pct = 0.0;
    switch (goalType) {
      case CalorieGoalType.maintenance:
        pct = (actual / target).clamp(0.0, 1.0);
        break;
      case CalorieGoalType.deficit:
        pct = (actual <= target) ? 1.0 : (target / actual).clamp(0.0, 1.0);
        break;
      case CalorieGoalType.surplus:
        pct = (actual >= target) ? 1.0 : (actual / target).clamp(0.0, 1.0);
        break;
      default:
        pct = 0.0;
    }
    return pct * 100.0;
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

  List<String> _getTips() {
    List<String> tips = [];
    if ((_stepsController.text.isNotEmpty &&
        int.tryParse(_stepsController.text) != null &&
        _userTargets != null &&
        _userTargets!['stepGoal'] != null &&
        int.parse(_stepsController.text) < _userTargets!['stepGoal'])) {
      tips.add('Try to walk more steps tomorrow for a higher score.');
    }
    if (!_workoutsCompleted) {
      tips.add('Logging a workout will boost your points!');
    }
    if ((_sleepHoursController.text.isNotEmpty &&
        double.tryParse(_sleepHoursController.text) != null &&
        _userTargets != null &&
        _userTargets!['sleepTarget'] != null &&
        (double.parse(_sleepHoursController.text) -
                    (_userTargets!['sleepTarget'] as num))
                .abs() >
            0.5)) {
      tips.add(
          'Aim to sleep within half an hour of your target for full points.');
    }
    if (!_supplementsTaken) {
      tips.add('Don\'t forget your supplements for extra points.');
    }
    if ((_proteinGramsController.text.isNotEmpty &&
        int.tryParse(_proteinGramsController.text) != null &&
        _userTargets != null &&
        _userTargets!['proteinTarget'] != null &&
        int.parse(_proteinGramsController.text) <
            _userTargets!['proteinTarget'])) {
      tips.add('Hit your protein target for a better score.');
    }
    if ((_waterIntakeController.text.isNotEmpty &&
        int.tryParse(_waterIntakeController.text) != null &&
        _userTargets != null &&
        _userTargets!['waterGoal'] != null &&
        int.parse(_waterIntakeController.text) < _userTargets!['waterGoal'])) {
      tips.add('Drink enough water to get max points.');
    }
    if ((_caloriesConsumedController.text.isNotEmpty &&
        int.tryParse(_caloriesConsumedController.text) != null &&
        _userTargets != null &&
        _userTargets!['calorieGoal'] != null)) {
      final int cal = int.parse(_caloriesConsumedController.text);
      final double goal = (_userTargets!['calorieGoal'] as num).toDouble();
      if ((cal - goal).abs() > goal * 0.20) {
        tips.add('Try to stay closer to your calorie target.');
      }
    }
    if (tips.isEmpty) tips.add('Great job! Keep up the consistency.');
    return tips;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Daily Progress'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Scoring System Info',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('How scoring works'),
                  content: const Text('If nothing is logged at all: -25 pts\n'
                      'If you log anything (even one metric or didn\'t track): minimum -15 pts\n'
                      'Didn\'t track (honest): +25 pts for that metric\n'
                      '0–49% of target: 0 pts\n'
                      '50–69%: 39 pts\n'
                      '70–89%: 79 pts\n'
                      '90–100%+: 100 pts\n\n'
                      'So you never drop below -15 unless you skip everything!'),
                  actions: [
                    TextButton(
                      child: const Text('Got it'),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  ],
                ),
              );
            },
          ),
        ],
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
                      ElevatedButton.icon(
                        onPressed: () => _selectDate(context),
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          'Logging for: ${DateFormat('EEE, MMM d,yyyy').format(_selectedDate)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor:
                              Theme.of(context).colorScheme.tertiaryContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildInputWithDidntTrack(
                        controller: _stepsController,
                        label: "Steps",
                        hint: "e.g., 10000",
                        keyboardType: TextInputType.number,
                        targetField: 'stepGoal',
                        unit: 'steps',
                        didntTrackValue: _didntTrackSteps,
                        onDidntTrackChanged: (val) =>
                            setState(() => _didntTrackSteps = val),
                      ),
                      _buildToggleField(
                        'Workouts Completed',
                        _workoutsCompleted,
                        (bool value) {
                          setState(() {
                            _workoutsCompleted = value;
                          });
                        },
                      ),
                      _buildInputWithDidntTrack(
                        controller: _caloriesConsumedController,
                        label: "Calories Consumed",
                        hint: "e.g., 2000",
                        keyboardType: TextInputType.number,
                        targetField: 'calorieGoal',
                        unit: 'calories',
                        didntTrackValue: _didntTrackCalories,
                        onDidntTrackChanged: (val) =>
                            setState(() => _didntTrackCalories = val),
                      ),
                      _buildInputField(
                        _sleepHoursController,
                        'Sleep Hours',
                        'e.g., 7.5',
                        const TextInputType.numberWithOptions(decimal: true),
                        'sleepTarget',
                        unit: 'hours',
                      ),
                      _buildInputWithDidntTrack(
                        controller: _proteinGramsController,
                        label: "Protein Grams",
                        hint: "e.g., 120",
                        keyboardType: TextInputType.number,
                        targetField: 'proteinTarget',
                        unit: 'grams',
                        didntTrackValue: _didntTrackProtein,
                        onDidntTrackChanged: (val) =>
                            setState(() => _didntTrackProtein = val),
                      ),
                      _buildToggleField(
                        'Supplements Taken',
                        _supplementsTaken,
                        (bool value) {
                          setState(() {
                            _supplementsTaken = value;
                          });
                        },
                      ),
                      _buildInputWithDidntTrack(
                        controller: _waterIntakeController,
                        label: "Water Intake (ml)",
                        hint: "e.g., 3000",
                        keyboardType: TextInputType.number,
                        targetField: 'waterGoal',
                        unit: 'ml',
                        didntTrackValue: _didntTrackWater,
                        onDidntTrackChanged: (val) =>
                            setState(() => _didntTrackWater = val),
                      ),
                      _buildInputField(
                        _weightController,
                        'Weight',
                        'e.g., 80',
                        TextInputType.numberWithOptions(decimal: true),
                        'weightGoal',
                        unit: 'kg',
                      ),
                      // MOOD SLIDER
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Mood (1 = 😞, 5 = 😄)'),
                                Slider(
                                  value: _mood.toDouble(),
                                  min: 1,
                                  max: 5,
                                  divisions: 4,
                                  label: '$_mood',
                                  onChanged: (val) {
                                    setState(() {
                                      _mood = val.round();
                                    });
                                  },
                                ),
                                Center(
                                  child: Text(
                                    'Current mood: $_mood',
                                    style: TextStyle(
                                      color: Colors.blueGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: _saveDailyData,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 55),
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Save Data',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      if (_lastCalculatedDailyScore != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 15),
                          child: Column(
                            children: [
                              Text(
                                'Your Daily Score:',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                              ),
                              if (_lastCalculatedPercent != null)
                                Column(
                                  children: [
                                    const SizedBox(height: 10),
                                    LinearProgressIndicator(
                                      value: (_lastCalculatedPercent! / 100)
                                          .clamp(0.0, 1.0),
                                      minHeight: 10,
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        _getScoreColor(
                                            _lastCalculatedDailyScore!),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'You hit ${_lastCalculatedPercent!.toStringAsFixed(1)}% of your goal!',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    if (_lastCalculatedPercent! >= 60)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          'YAY 🎉 you hit over 60% of your goal so you get ${_lastCalculatedDailyScore!.toStringAsFixed(1)} points!',
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '${_lastCalculatedDailyScore!.toStringAsFixed(1)} pts',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _getScoreColor(
                                          _lastCalculatedDailyScore!),
                                    ),
                              ),
                              const SizedBox(height: 10),
                              if (_didntTrackSteps ||
                                  _didntTrackCalories ||
                                  _didntTrackProtein ||
                                  _didntTrackWater)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 5.0, bottom: 5.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.emoji_emotions,
                                          color: Colors.orange, size: 18),
                                      const SizedBox(width: 5),
                                      const Text(
                                        "You got partial credit for being honest about not tracking today.",
                                        style: TextStyle(
                                            color: Colors.orange,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              Card(
                                color: Colors.amber[50],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                child: Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Tips for Doing Better Tomorrow:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange),
                                      ),
                                      ..._getTips()
                                          .map((tip) => Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 6.0),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('• ',
                                                        style: TextStyle(
                                                            fontSize: 15,
                                                            color: Colors
                                                                .black87)),
                                                    Expanded(
                                                      child: Text(tip,
                                                          style: const TextStyle(
                                                              color: Colors
                                                                  .black87)),
                                                    ),
                                                  ],
                                                ),
                                              ))
                                          .toList()
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
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

  Color _getScoreColor(double score) {
    if (score >= 50) {
      return Colors.green.shade700;
    } else if (score >= 20) {
      return Colors.lightGreen.shade700;
    } else if (score >= 0) {
      return Colors.orange.shade700;
    } else {
      return Colors.red.shade700;
    }
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label,
    String hint,
    TextInputType keyboardType,
    String targetField, {
    String unit = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            keyboardType: keyboardType,
            onChanged: (value) {
              setState(() {});
            },
          ),
          _buildProjectionText(
              label, controller.text, targetField, keyboardType, unit),
        ],
      ),
    );
  }

  Widget _buildInputWithDidntTrack({
    required TextEditingController controller,
    required String label,
    required String hint,
    required TextInputType keyboardType,
    required String targetField,
    required String unit,
    required bool didntTrackValue,
    required ValueChanged<bool> onDidntTrackChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            keyboardType: keyboardType,
            onChanged: (value) {
              setState(() {});
            },
            enabled: !didntTrackValue,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text("Didn't track", style: TextStyle(fontSize: 12)),
              Switch(
                value: didntTrackValue,
                onChanged: onDidntTrackChanged,
                activeColor: Colors.orange,
              ),
            ],
          ),
          _buildProjectionText(
              label, controller.text, targetField, keyboardType, unit),
        ],
      ),
    );
  }

  Widget _buildToggleField(
      String label, bool value, ValueChanged<bool> onChanged,
      [String? targetField]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  Switch(
                    value: value,
                    onChanged: (newValue) {
                      onChanged(newValue);
                    },
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              if (targetField != null)
                _buildProjectionText(label, value, targetField, null),
              if (targetField == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                  child: Text(
                    value
                        ? '$label: Logged as completed.'
                        : '$label: Not yet logged.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: value ? Colors.green : Colors.orange,
                    ),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectionText(String label, dynamic currentValue,
      String targetField, TextInputType? keyboardType,
      [String unit = '']) {
    if (_userTargets == null || _userTargets!.isEmpty) {
      return const SizedBox.shrink();
    }

    dynamic target = _userTargets![targetField];
    if (target == null ||
        (keyboardType != null && (target is num && target <= 0))) {
      return const SizedBox.shrink();
    }

    String projection = '';
    Color textColor = Colors.grey;

    try {
      if (keyboardType == TextInputType.number ||
          keyboardType == TextInputType.numberWithOptions(decimal: true)) {
        double actual = double.tryParse(currentValue.toString()) ?? 0.0;
        double targetValue = target.toDouble();

        if (label == 'Calories Consumed') {
          final calorieGoalTypeString =
              _userTargets!['calorieGoalType'] ?? 'maintenance';
          final CalorieGoalType calorieGoalType =
              CalorieGoalType.values.firstWhere(
            (e) => e.toString().split('.').last == calorieGoalTypeString,
            orElse: () => CalorieGoalType.maintenance,
          );

          if (calorieGoalType == CalorieGoalType.deficit) {
            if (actual <= targetValue) {
              projection = 'Within deficit!';
              textColor = Colors.green;
            } else {
              double excess = actual - targetValue;
              projection = 'Over by ${excess.toStringAsFixed(0)} $unit.';
              textColor = Colors.red;
            }
          } else if (calorieGoalType == CalorieGoalType.surplus) {
            if (actual >= targetValue) {
              projection = 'Met surplus goal!';
              textColor = Colors.green;
            } else {
              double needed = targetValue - actual;
              projection =
                  '${needed.toStringAsFixed(0)} $unit needed for surplus.';
              textColor = Colors.orange;
            }
          } else {
            double deviation = (actual - targetValue).abs();
            if (deviation <= (targetValue * 0.10)) {
              projection = 'Close to maintenance goal!';
              textColor = Colors.green;
            } else {
              projection =
                  '${deviation.toStringAsFixed(0)} $unit off maintenance.';
              textColor = Colors.orange;
            }
          }
        } else if (label == 'Sleep Hours') {
          double deviation = (actual - targetValue).abs();
          if (deviation <= 0.5) {
            projection = 'Close to sleep goal!';
            textColor = Colors.green;
          } else if (actual > targetValue) {
            projection =
                '${(actual - targetValue).toStringAsFixed(1)} $unit over target.';
            textColor = Colors.orange;
          } else {
            projection =
                '${(targetValue - actual).toStringAsFixed(1)} $unit needed.';
            textColor = Colors.red;
          }
        } else {
          if (actual >= targetValue) {
            projection =
                'Target met! ${(actual - targetValue).toStringAsFixed(0)} $unit over.';
            textColor = Colors.green;
          } else {
            double needed = targetValue - actual;
            projection = '${needed.toStringAsFixed(0)} $unit needed.';
            textColor = Colors.orange;
          }
        }
      } else if (currentValue is bool) {
        return const SizedBox.shrink();
      }
    } catch (e) {
      print('Error calculating projection for $label: $e');
      projection = 'N/A';
      textColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0, left: 4.0),
      child: Text(
        projection,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: textColor,
        ),
      ),
    );
  }
}
