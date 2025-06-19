import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/weekly_score.dart';
import '../utils/enums.dart';
import '../widgets/score_card.dart';
import 'input_for_today.dart';

// --- Info Page Widget ---
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About FitIndex'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("🏆", style: TextStyle(fontSize: 32)),
                const SizedBox(width: 10),
                Text(
                  "FitIndex",
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              "Your Ultimate Fitness Companion",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 10),
            const Text(
              "FitIndex is built to make daily healthy habits fun, competitive, and easy to track! "
              "Log your nutrition, workouts, sleep, supplements, water, weight, and mood every day. "
              "Earn points for consistency and climb the global leaderboard.\n",
              style: TextStyle(fontSize: 16, height: 1.7),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                "Stay consistent, rack up streaks, and reach the ultimate rank: Apex Predator. "
                "Show your friends who’s boss—every day, every week, every log!",
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
            const Divider(height: 38, thickness: 1.5),
            Text(
              "How FitIndex Works",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 14),
            RichText(
              text: TextSpan(
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontSize: 15, height: 1.6),
                children: const [
                  TextSpan(
                    text: "• Daily Log:\n",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        "Just log your stats every day—nutrition, workouts, sleep, water, supplements, weight, and mood. "
                        "Everything else will fall into place! On your Home screen, you’ll see today’s log and how you’re progressing.\n\n",
                  ),
                  TextSpan(
                    text: "• Daily Score:\n",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        "Your daily score is based on how close you get to your targets. "
                        "Aim for 100 every day! (Note: Weight and mood are tracked for your reference—they don’t affect your score.)\n\n",
                  ),
                  TextSpan(
                    text: "• Weekly Score & Ranks:\n",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        "See how well you’ve done over the past 7 days. Ranks like Wood, Iron, Bronze, Silver, Gold, Platinum, Diamond, and Apex Predator show your weekly performance. "
                        "Green bars all week? You’re crushing it!\n\n",
                  ),
                  TextSpan(
                    text: "• Streaks:\n",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        "Maintain a streak by scoring above 80% of your daily goals. "
                        "Keep the fire emoji 🔥 alive by being an overachiever day after day!\n\n",
                  ),
                  TextSpan(
                    text: "• Global Rank:\n",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        "Your global score is the sum of all your daily efforts. "
                        "Do well, and it rises. Fall behind, and it’ll drop. "
                        "This is where you compete with friends and climb the leaderboard—higher score, higher bragging rights.\nTo add someone go to your profile page and put in their emails!",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Center(
              child: Text(
                "Version 2.0.1\nMade by Faris Alblooki",
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _todayLogData;
  bool _isLoadingTodayData = true;

  WeeklyScore? _currentWeeklyScore;
  bool _isLoadingWeeklyScore = true;

  Map<String, dynamic>? _userTargets;
  String? _userName;
  double? _globalRankScore;

  bool _checkedMissedDays = false;
  bool _checkingMissedDays = true;

  @override
  void initState() {
    super.initState();
    _checkAndHandleMissedDays();
  }

  Future<void> _startEverythingElse() async {
    await _loadAllData();
    setState(() {});
  }

  // --- Check for missed days, update globalRankScore, show dialog with close ---
  Future<void> _checkAndHandleMissedDays() async {
    if (_checkedMissedDays) return;
    _checkedMissedDays = true;

    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _checkingMissedDays = false);
      return;
    }

    final dailyLogsCollection =
        _firestore.collection('users').doc(user.uid).collection('daily_logs');
    DateTime today = DateTime.now();
    DateTime yesterday = today.subtract(const Duration(days: 1));

    // --- NEW: Get the very first log's date. ---
    final firstLogSnap = await dailyLogsCollection
        .orderBy('timestamp', descending: false)
        .limit(1)
        .get();

    if (firstLogSnap.docs.isEmpty) {
      // No logs at all, skip penalty.
      setState(() => _checkingMissedDays = false);
      await _startEverythingElse();
      return;
    }

    // Either from 'timestamp' or from doc id:
    DateTime firstLogDate;
    final doc = firstLogSnap.docs.first;
    if (doc.data().containsKey('timestamp') && doc['timestamp'] != null) {
      firstLogDate = (doc['timestamp'] as Timestamp).toDate();
      firstLogDate =
          DateTime(firstLogDate.year, firstLogDate.month, firstLogDate.day);
    } else {
      final id = doc.id; // e.g. '2024-06-14'
      final parts = id.split('-');
      firstLogDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }

    // 1. Don't check today anymore. Start from yesterday.
    List<DateTime> missingDays = [];
    DateTime checkDate = yesterday;
    bool foundLoggedDay = false;

    while (!foundLoggedDay && !checkDate.isBefore(firstLogDate)) {
      final dateId = _getDateId(checkDate);
      final doc = await dailyLogsCollection.doc(dateId).get();

      if (doc.exists) {
        foundLoggedDay = true;
        break;
      } else {
        missingDays.add(checkDate);
        checkDate = checkDate.subtract(const Duration(days: 1));
      }
      if (missingDays.length > 60) break;
    }

    if (missingDays.isEmpty) {
      setState(() => _checkingMissedDays = false);
      await _startEverythingElse();
      return;
    }

    // 3. For each missing, create a zeroed log with -25 score
    for (DateTime date in missingDays) {
      final dateId = _getDateId(date);
      await dailyLogsCollection.doc(dateId).set({
        'stepsPerDay': 0,
        'workoutsCompleted': false,
        'caloriesConsumed': 0,
        'sleepHours': 0.0,
        'proteinGrams': 0,
        'supplementsTaken': false,
        'waterIntake': 0,
        'weight': 0.0,
        'mood': 3,
        'timestamp': FieldValue.serverTimestamp(),
        'dailyScore': -25,
        'percentScore': 0.0,
        'didntTrackSteps': false,
        'didntTrackCalories': false,
        'didntTrackProtein': false,
        'didntTrackWater': false,
      }, SetOptions(merge: true));
    }

    // 4. Update globalRankScore with the penalty -- clamp at -100
    final userDocRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    double currentGlobalRankScore =
        (userDoc.data()?['globalRankScore'] as num?)?.toDouble() ?? 0.0;
    double newGlobalRankScore =
        currentGlobalRankScore + (-25 * missingDays.length);

    // --- Clamp globalRankScore at -100 before writing to DB ---
    if (newGlobalRankScore < -100) newGlobalRankScore = -100;

    await userDocRef.set({
      'globalRankScore': newGlobalRankScore,
      'lastUpdatedRank': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Show penalty dialog after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Missed Days Detected"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "You have missed ${missingDays.length} day${missingDays.length > 1 ? 's' : ''}, which means you get a",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 18),
              Text(
                "-${25 * missingDays.length}",
                style: const TextStyle(
                  fontSize: 38,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "penalty.",
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 17),
              ),
              const SizedBox(height: 14),
              const Text(
                "Go back to the input screen and fill in your missed days to get back your points!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              // --- Friendly note about minimum score ---
              const Text(
                "No worries—your global score can't go below -100! This is your comeback moment. Keep logging and bounce back stronger.",
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const InputForTodayScreen()),
                );
              },
              child: const Text(
                "Go to Input Screen",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: const Text(
                "Close",
                style: TextStyle(fontWeight: FontWeight.normal),
              ),
            ),
          ],
        ),
      );
    });

    setState(() => _checkingMissedDays = false);
    await _startEverythingElse();
  }

  String _getDateId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAllData() async {
    await _loadTodayLogData();
    await _fetchGlobalRankScore();
    await _fetchUserName();
    await _fetchDataAndBuildWeeklyScore();
  }

  Future<void> _fetchUserName() async {
    final user = _auth.currentUser;
    String? name;

    // 1. Try Auth displayName
    if (user != null &&
        user.displayName != null &&
        user.displayName!.isNotEmpty) {
      name = user.displayName;
    } else if (user != null) {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists &&
          userDoc.data() != null &&
          userDoc.data()!.containsKey('name')) {
        name = userDoc.data()!['name'];
      }
    }

    String? firstName;
    if (name != null && name.trim().isNotEmpty) {
      firstName = name.trim().split(' ').first;
    }

    setState(() {
      _userName = firstName;
    });
  }

  Future<void> _fetchGlobalRankScore() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _globalRankScore = null;
      });
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        double score =
            (userDoc.data()!['globalRankScore'] as num?)?.toDouble() ?? 0.0;
        // Clamp for display
        if (score < -100) score = -100;
        setState(() {
          _globalRankScore = score;
        });
      } else {
        setState(() {
          _globalRankScore = null;
        });
      }
    } catch (e) {
      setState(() {
        _globalRankScore = null;
      });
    }
  }

  Future<void> _loadTodayLogData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingTodayData = false;
        _todayLogData = null;
      });
      return;
    }

    setState(() {
      _isLoadingTodayData = true;
    });

    try {
      final docId = _getDateId(DateTime.now());
      final docSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('daily_logs')
          .doc(docId)
          .get();

      if (docSnapshot.exists) {
        setState(() {
          _todayLogData = docSnapshot.data();
        });
      } else {
        setState(() {
          _todayLogData = null;
        });
      }
    } catch (e) {
      setState(() {
        _todayLogData = null;
      });
    } finally {
      setState(() {
        _isLoadingTodayData = false;
      });
    }
  }

  Future<void> _fetchDataAndBuildWeeklyScore() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingWeeklyScore = false;
        _currentWeeklyScore = null;
      });
      return;
    }

    setState(() {
      _isLoadingWeeklyScore = true;
    });

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        _userTargets = userDoc.data();
      } else {
        _userTargets = {};
      }

      final int proteinTarget = _userTargets?['proteinTarget'] ?? 0;
      final int calorieGoal = _userTargets?['calorieGoal'] ?? 0;
      final String calorieGoalTypeString =
          _userTargets?['calorieGoalType'] ?? 'maintenance';
      final CalorieGoalType calorieGoalType = CalorieGoalType.values.firstWhere(
        (e) => e.toString().split('.').last == calorieGoalTypeString,
        orElse: () => CalorieGoalType.maintenance,
      );
      final int stepGoal = _userTargets?['stepGoal'] ?? 0;
      final int waterGoal = _userTargets?['waterGoal'] ?? 0;
      final double sleepTarget =
          (_userTargets?['sleepTarget'] ?? 8.0).toDouble();
      final int workoutGoal =
          (_userTargets?['workoutGoal'] as num?)?.toInt() ?? 0;

      final List<String> last7Days = List.generate(
          7,
          (index) =>
              _getDateId(DateTime.now().subtract(Duration(days: 6 - index))));

      List<int> stepsPerDay = List.filled(7, 0);
      List<bool> workoutsCompleted = List.filled(7, false);
      List<int> caloriesConsumed = List.filled(7, 0);
      List<double> sleepHours = List.filled(7, 0.0);
      List<int> proteinGrams = List.filled(7, 0);
      List<bool> supplementsTaken = List.filled(7, false);
      List<int> waterIntake = List.filled(7, 0);

      final dailyLogsCollection =
          _firestore.collection('users').doc(user.uid).collection('daily_logs');

      for (int i = 0; i < last7Days.length; i++) {
        final String dateId = last7Days[i];
        final doc = await dailyLogsCollection.doc(dateId).get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          stepsPerDay[i] = data['stepsPerDay'] ?? 0;
          workoutsCompleted[i] = data['workoutsCompleted'] ?? false;
          caloriesConsumed[i] = data['caloriesConsumed'] ?? 0;
          sleepHours[i] = (data['sleepHours'] ?? 0.0).toDouble();
          proteinGrams[i] = data['proteinGrams'] ?? 0;
          supplementsTaken[i] = data['supplementsTaken'] ?? false;
          waterIntake[i] = data['waterIntake'] ?? 0;
        }
      }

      _currentWeeklyScore = WeeklyScore(
          stepsPerDay: stepsPerDay,
          workoutsCompleted: workoutsCompleted,
          caloriesConsumed: caloriesConsumed,
          sleepHours: sleepHours,
          proteinGrams: proteinGrams,
          proteinTarget: proteinTarget,
          supplementsTaken: supplementsTaken,
          waterIntake: waterIntake,
          calorieGoal: calorieGoal,
          calorieGoalType: calorieGoalType,
          stepGoal: stepGoal,
          waterGoal: waterGoal,
          sleepTarget: sleepTarget,
          workoutGoal: workoutGoal);
    } catch (e) {
      _currentWeeklyScore = null;
    } finally {
      setState(() {
        _isLoadingWeeklyScore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingMissedDays) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final Color primaryColor = Theme.of(context).colorScheme.primary;

    // Clamp displayed score
    double? displayScore = _globalRankScore;
    if (displayScore != null && displayScore < -100) displayScore = -100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'About the App',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InfoScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _userName != null && _userName!.isNotEmpty
                    ? 'Hello, ${_userName!.split(' ')[0]} 👋'
                    : 'Hello there! 👋',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
              ),
            ),
            // ---- GLOBAL SCORE PLAQUE ----
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 28, horizontal: 36),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withOpacity(0.95),
                        Theme.of(context)
                            .colorScheme
                            .tertiary
                            .withOpacity(0.90),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Global Score',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      displayScore == null
                          ? const Text(
                              'N/A',
                              style: TextStyle(
                                  fontSize: 40,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  '🏆',
                                  style: TextStyle(fontSize: 38),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  displayScore.toStringAsFixed(1),
                                  style: TextStyle(
                                    fontSize: 46,
                                    fontWeight: FontWeight.bold,
                                    color: _getScoreColor(displayScore),
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                      if (displayScore != null && displayScore < 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 15.0),
                          child: Text(
                            "Don't stress, -100 is the lowest it goes! This is your chance to bounce back. Every day is a new start.",
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // ---- END PLAQUE ----

            Text(
              'Your Daily Progress at a Glance',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Log (${_getDateId(DateTime.now())}) 🗓️",
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    _isLoadingTodayData
                        ? const Center(child: CircularProgressIndicator())
                        : _todayLogData != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDataRow(
                                      'Steps',
                                      '🦶',
                                      _todayLogData!['stepsPerDay']
                                              ?.toString() ??
                                          'N/A'),
                                  _buildDataRow(
                                      'Worked Out',
                                      '💪',
                                      _todayLogData!['workoutsCompleted'] ==
                                              true
                                          ? '✔️'
                                          : '❌'),
                                  _buildDataRow(
                                      'Calories Consumed',
                                      '🍔',
                                      _todayLogData!['caloriesConsumed']
                                              ?.toString() ??
                                          'N/A'),
                                  _buildDataRow(
                                      'Sleep Hours',
                                      '😴',
                                      _todayLogData!['sleepHours']
                                              ?.toString() ??
                                          'N/A'),
                                  _buildDataRow(
                                      'Protein Grams',
                                      '🍗',
                                      _todayLogData!['proteinGrams']
                                              ?.toString() ??
                                          'N/A'),
                                  _buildDataRow(
                                      'Supplements Taken',
                                      '💊',
                                      _todayLogData!['supplementsTaken'] == true
                                          ? '✔️'
                                          : '❌'),
                                  _buildDataRow(
                                      'Water Intake (ml)',
                                      '💧',
                                      _todayLogData!['waterIntake']
                                              ?.toString() ??
                                          'N/A'),
                                  _buildDataRow(
                                    'Weight',
                                    '⚖️',
                                    _todayLogData!['weight'] != null &&
                                            _todayLogData!['weight'] > 0
                                        ? _todayLogData!['weight'].toString() +
                                            ' kg'
                                        : 'N/A',
                                  ),
                                  _buildDataRow(
                                    'Mood',
                                    '🙂',
                                    _todayLogData!['mood'] != null &&
                                            (_todayLogData!['mood'] as int) >=
                                                1 &&
                                            (_todayLogData!['mood'] as int) <= 5
                                        ? _moodEmoji(_todayLogData!['mood'])
                                        : 'N/A',
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  const Text(
                                    'No data logged for today yet. Get started!',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  const SizedBox(height: 10),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Log Today\'s Data'),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                const InputForTodayScreen()),
                                      ).then((_) {
                                        _loadAllData();
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onSecondary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            _isLoadingWeeklyScore
                ? const Center(child: CircularProgressIndicator())
                : _currentWeeklyScore != null
                    ? ScoreCard(weeklyScore: _currentWeeklyScore!)
                    : const Text(
                        'Oops! No weekly score yet. Make sure you\'ve logged some data and set your goals in your Profile.',
                        style: TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
            const SizedBox(height: 40),
            const Column(
              children: [
                Text(
                  'App version: 2.0.1',
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
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 75) {
      return Colors.green.shade700;
    } else if (score >= 50) {
      return Colors.lightGreen.shade700;
    } else if (score >= 25) {
      return Colors.orange.shade700;
    } else {
      return Colors.red.shade700;
    }
  }

  Widget _buildDataRow(String label, String emoji, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                '$label:',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _moodEmoji(int mood) {
    switch (mood) {
      case 1:
        return '😞 Very Low';
      case 2:
        return '😕 Low';
      case 3:
        return '😐 Neutral';
      case 4:
        return '🙂 Good';
      case 5:
        return '😄 Great';
      default:
        return 'N/A';
    }
  }
}
