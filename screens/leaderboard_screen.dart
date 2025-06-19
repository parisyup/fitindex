import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fit_index/utils/enums.dart'; // Make sure this path is correct
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/weekly_score.dart' show WeeklyScore;
import '../widgets/score_card.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  double _myGlobalScore = 0.0;
  List<Map<String, dynamic>> _friendsData = [];
  List<Map<String, dynamic>> _leaderboardData = [];
  bool _isLoadingLeaderboard = true;
  String? _leaderboardErrorMessage;

  String? _selectedFriendUid;
  String? _selectedFriendDisplayName;

  TrendType _selectedFriendTrend = TrendType.steps;
  List<Map<String, dynamic>> _friendDailyLogsData = [];
  bool _isLoadingFriendTrends = false;
  String? _friendTrendErrorMessage;

  DateTime _selectedDateForFriendStats = DateTime.now();
  Map<String, dynamic>? _selectedFriendDailyStats;
  bool _isLoadingSelectedFriendDateStats = false;
  String? _selectedFriendDateStatsErrorMessage;

  double _minY = 0;
  double _maxY = 0;

  WeeklyScore? _friendWeeklyScore;
  bool _isLoadingFriendWeeklyScore = false;

  @override
  void initState() {
    super.initState();
    _fetchLeaderboardData();
  }

  String _getDateId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchLeaderboardData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _leaderboardErrorMessage = 'Please log in to view the leaderboard.';
        _isLoadingLeaderboard = false;
      });
      return;
    }

    setState(() {
      _isLoadingLeaderboard = true;
      _leaderboardErrorMessage = null;
      _leaderboardData = [];
      _friendsData = [];
    });

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        _leaderboardErrorMessage = 'Your user profile not found.';
        return;
      }
      final userData = userDoc.data()!;
      _myGlobalScore = (userData['globalRankScore'] as num?)?.toDouble() ?? 0.0;
      final List<dynamic> friendUids = userData['friends'] ?? [];

      _leaderboardData.add({
        'uid': user.uid,
        'displayName': user.displayName ?? 'You',
        'globalRankScore': _myGlobalScore,
        'isMe': true,
      });

      List<Map<String, dynamic>> fetchedFriends = [];
      for (String friendUid in friendUids) {
        final friendDoc =
            await _firestore.collection('users').doc(friendUid).get();
        if (friendDoc.exists && friendDoc.data() != null) {
          final friendData = friendDoc.data()!;
          fetchedFriends.add({
            'uid': friendUid,
            'displayName':
                friendData['name'] ?? friendData['email'] ?? 'Unknown',
            'globalRankScore':
                (friendData['globalRankScore'] as num?)?.toDouble() ?? 0.0,
            'isMe': false,
          });
        }
      }
      _friendsData = fetchedFriends;

      _leaderboardData.addAll(fetchedFriends);
      _leaderboardData
          .sort((a, b) => b['globalRankScore'].compareTo(a['globalRankScore']));

      if (_friendsData.isNotEmpty) {
        _selectedFriendUid = _friendsData.first['uid'];
        _selectedFriendDisplayName = _friendsData.first['displayName'];
        _fetchFriendTrendData(_selectedFriendUid!, _selectedFriendTrend);
        _loadSelectedFriendDailyStats(
            _selectedFriendUid!, _selectedDateForFriendStats);
        await _fetchFriendWeeklyScore(_selectedFriendUid!);
      }
    } catch (e) {
      print('DEBUG: Error fetching leaderboard data: $e');
      _leaderboardErrorMessage = 'Error loading leaderboard: ${e.toString()}';
    } finally {
      setState(() {
        _isLoadingLeaderboard = false;
      });
    }
  }

  Future<void> _fetchFriendTrendData(
      String friendUid, TrendType trendType) async {
    setState(() {
      _isLoadingFriendTrends = true;
      _friendTrendErrorMessage = null;
      _friendDailyLogsData = [];
      _selectedFriendTrend = trendType;
    });

    try {
      final now = DateTime.now();
      final List<String> last30Days = List.generate(
          30, (index) => _getDateId(now.subtract(Duration(days: 29 - index))));

      List<Map<String, dynamic>> fetchedData = [];

      final dailyLogsCollection = _firestore
          .collection('users')
          .doc(friendUid)
          .collection('daily_logs');

      if (trendType == TrendType.globalScore) {
        for (String dateId in last30Days) {
          final dailyDoc = await dailyLogsCollection.doc(dateId).get();

          double dailyScore = 0.0;
          if (dailyDoc.exists && dailyDoc.data() != null) {
            final data = dailyDoc.data()!;
            dailyScore = data["dailyScore"];

            fetchedData.add({
              'dateId': dateId,
              'isLogged': true,
              'globalScore': dailyScore,
              'stepsPerDay': data['stepsPerDay'] ?? 0,
              'waterIntake': data['waterIntake'] ?? 0,
              'caloriesConsumed': data['caloriesConsumed'] ?? 0,
              'proteinGrams': data['proteinGrams'] ?? 0,
              'sleepHours': data['sleepHours'] ?? 0.0,
              'workoutsCompleted': data['workoutsCompleted'] ?? false,
              'supplementsTaken': data['supplementsTaken'] ?? false,
              'weight': data['weight'] ?? 0.0,
              'mood': data['mood'] ?? 0,
            });
          } else {
            fetchedData.add({
              'dateId': dateId,
              'isLogged': false,
              'globalScore': 0.0,
              'stepsPerDay': 0,
              'waterIntake': 0,
              'caloriesConsumed': 0,
              'proteinGrams': 0,
              'sleepHours': 0.0,
              'workoutsCompleted': false,
              'supplementsTaken': false,
              'weight': 0.0,
              'mood': 0,
            });
          }
        }
      } else {
        for (String dateId in last30Days) {
          final doc = await dailyLogsCollection.doc(dateId).get();
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            data['dateId'] = dateId;
            data['isLogged'] = true;
            fetchedData.add(data);
          } else {
            fetchedData.add({
              'dateId': dateId,
              'isLogged': false,
              'stepsPerDay': 0,
              'caloriesConsumed': 0,
              'sleepHours': 0.0,
              'proteinGrams': 0,
              'workoutsCompleted': false,
              'supplementsTaken': false,
              'waterIntake': 0,
              'weight': 0.0,
              'mood': 0,
            });
          }
        }
      }

      setState(() {
        _friendDailyLogsData = fetchedData;
        _isLoadingFriendTrends = false;
      });
    } catch (e) {
      print('DEBUG: Error fetching friend trend data: $e');
      setState(() {
        _friendTrendErrorMessage =
            'Error loading friend\'s trends: ${e.toString()}';
        _isLoadingFriendTrends = false;
      });
    }
  }

  Future<void> _loadSelectedFriendDailyStats(
      String friendUid, DateTime date) async {
    setState(() {
      _isLoadingSelectedFriendDateStats = true;
      _selectedDateForFriendStats = date;
      _selectedFriendDailyStats = null;
      _selectedFriendDateStatsErrorMessage = null;
    });

    try {
      final docId = _getDateId(date);
      final docSnapshot = await _firestore
          .collection('users')
          .doc(friendUid)
          .collection('daily_logs')
          .doc(docId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;

        setState(() {
          _selectedFriendDailyStats = data;
        });
      } else {
        setState(() {
          _selectedFriendDailyStats = null;
        });
      }
    } catch (e) {
      print('DEBUG: Error loading selected friend date stats: $e');
      setState(() {
        _selectedFriendDailyStats = null;
        _selectedFriendDateStatsErrorMessage =
            'Error loading stats: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoadingSelectedFriendDateStats = false;
      });
    }
  }

  // --- Fetch Friend's Weekly Score ---
  Future<void> _fetchFriendWeeklyScore(String friendUid) async {
    setState(() {
      _isLoadingFriendWeeklyScore = true;
      _friendWeeklyScore = null;
    });

    try {
      final userDoc = await _firestore.collection('users').doc(friendUid).get();
      Map<String, dynamic>? userTargets = userDoc.exists ? userDoc.data() : {};

      final int proteinTarget = userTargets?['proteinTarget'] ?? 0;
      final int calorieGoal = userTargets?['calorieGoal'] ?? 0;
      final String calorieGoalTypeString =
          userTargets?['calorieGoalType'] ?? 'maintenance';
      final CalorieGoalType calorieGoalType = CalorieGoalType.values.firstWhere(
        (e) => e.toString().split('.').last == calorieGoalTypeString,
        orElse: () => CalorieGoalType.maintenance,
      );
      final int stepGoal = userTargets?['stepGoal'] ?? 0;
      final int waterGoal = userTargets?['waterGoal'] ?? 0;
      final double sleepTarget =
          (userTargets?['sleepTarget'] ?? 8.0).toDouble();
      final int workoutGoal =
          (userTargets?['workoutGoal'] as num?)?.toInt() ?? 0;

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

      final dailyLogsCollection = _firestore
          .collection('users')
          .doc(friendUid)
          .collection('daily_logs');

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

      setState(() {
        _friendWeeklyScore = WeeklyScore(
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
          workoutGoal: workoutGoal,
        );
      });
    } catch (e) {
      print('DEBUG: Error fetching friend weekly score: $e');
      setState(() {
        _friendWeeklyScore = null;
      });
    } finally {
      setState(() {
        _isLoadingFriendWeeklyScore = false;
      });
    }
  }

  String _calculateAverage(TrendType trendType) {
    if (trendType == TrendType.workedOut ||
        trendType == TrendType.supplementsTaken) {
      return 'N/A';
    }

    if (_friendDailyLogsData.isEmpty) return 'N/A';

    double total = 0;
    int count = 0;
    String fieldKey = trendType.toFirestoreKey();

    if (trendType == TrendType.globalScore) {
      fieldKey = 'globalScore';
    }

    for (var data in _friendDailyLogsData) {
      if (data['isLogged'] == true) {
        final value = (data[fieldKey] as num?)?.toDouble() ?? 0.0;
        total += value;
        count++;
      }
    }

    if (count == 0) return 'N/A';

    final average = total / count;
    if (trendType == TrendType.sleepHours ||
        trendType == TrendType.globalScore ||
        trendType == TrendType.weight ||
        trendType == TrendType.mood) {
      return average.toStringAsFixed(1);
    }
    return average.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard & Friend Stats'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      'Your Global Score',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isLoadingLeaderboard
                          ? 'Loading...'
                          : '${_myGlobalScore.toStringAsFixed(0)} points',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Friends Leaderboard 🏆',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _isLoadingLeaderboard
                ? const Center(child: CircularProgressIndicator())
                : _leaderboardErrorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            _leaderboardErrorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 16),
                          ),
                        ),
                      )
                    : _leaderboardData.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: Text(
                                'No friends added or no scores yet. Add friends on your profile!',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                            ),
                          )
                        : Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _leaderboardData.length,
                              itemBuilder: (context, index) {
                                final entry = _leaderboardData[index];
                                final bool isMe = entry['isMe'];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isMe
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .tertiary,
                                    child: Text(
                                      '#${index + 1}',
                                      style: TextStyle(
                                        color: isMe
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                            : Theme.of(context)
                                                .colorScheme
                                                .onTertiary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    entry['displayName'],
                                    style: TextStyle(
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isMe
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                    ),
                                  ),
                                  trailing: Text(
                                    '${entry['globalRankScore'].toStringAsFixed(0)} pts',
                                    style: TextStyle(
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isMe
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                      fontSize: 16,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
            const SizedBox(height: 40),
            Text(
              'View Friend\'s Stats & Trends 📈',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _friendsData.isEmpty && !_isLoadingLeaderboard
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        'Add friends from the profile page to view their stats here!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ),
                  )
                : Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedFriendUid,
                          hint: const Text('Select a friend'),
                          icon: const Icon(Icons.arrow_drop_down_rounded,
                              size: 28),
                          isExpanded: true,
                          onChanged: (String? newUid) async {
                            if (newUid != null) {
                              setState(() {
                                _selectedFriendUid = newUid;
                                _selectedFriendDisplayName =
                                    _friendsData.firstWhere((f) =>
                                        f['uid'] == newUid)['displayName'];
                                _isLoadingFriendTrends = true;
                                _isLoadingSelectedFriendDateStats = true;
                                _selectedFriendTrend = TrendType.steps;
                                _selectedDateForFriendStats = DateTime.now();
                              });
                              _fetchFriendTrendData(
                                  newUid, _selectedFriendTrend);
                              _loadSelectedFriendDailyStats(
                                  newUid, _selectedDateForFriendStats);
                              await _fetchFriendWeeklyScore(newUid);
                            }
                          },
                          items: _friendsData
                              .map<DropdownMenuItem<String>>((friend) {
                            return DropdownMenuItem<String>(
                              value: friend['uid'],
                              child: Text(
                                friend['displayName'],
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 20),
            if (_selectedFriendUid != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<TrendType>(
                          value: _selectedFriendTrend,
                          icon: const Icon(Icons.arrow_drop_down_rounded,
                              size: 28),
                          isExpanded: true,
                          onChanged: (TrendType? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedFriendTrend = newValue;
                              });
                              _fetchFriendTrendData(
                                  _selectedFriendUid!, newValue);
                            }
                          },
                          items: TrendType.values
                              .map<DropdownMenuItem<TrendType>>(
                                  (TrendType value) {
                            return DropdownMenuItem<TrendType>(
                              value: value,
                              child: Row(
                                children: [
                                  Text(
                                    value.toEmoji(),
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    value.toDisplayName(),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _isLoadingFriendTrends
                      ? const Center(child: CircularProgressIndicator())
                      : _friendTrendErrorMessage != null
                          ? Center(
                              child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text(
                                _friendTrendErrorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 16),
                              ),
                            ))
                          : _buildFriendTrendContent(),
                  const SizedBox(height: 40),
                  Text(
                    '${_selectedFriendDisplayName ?? 'Friend'}\'s Daily Stats 🗓️',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    readOnly: true,
                    controller: TextEditingController(
                        text: DateFormat('EEEE, MMM d, yyyy')
                            .format(_selectedDateForFriendStats)),
                    decoration: InputDecoration(
                      labelText: 'Select Date',
                      suffixIcon: Icon(Icons.calendar_today,
                          color: Theme.of(context).colorScheme.primary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceVariant
                          .withOpacity(0.2),
                    ),
                    onTap: () async {
                      DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: _selectedDateForFriendStats,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        helpText: 'Select a Log Date',
                        confirmText: 'SELECT',
                        cancelText: 'CANCEL',
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Theme.of(context).colorScheme.primary,
                                onPrimary:
                                    Theme.of(context).colorScheme.onPrimary,
                                onSurface:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (pickedDate != null &&
                          (pickedDate.day != _selectedDateForFriendStats.day ||
                              pickedDate.month !=
                                  _selectedDateForFriendStats.month ||
                              pickedDate.year !=
                                  _selectedDateForFriendStats.year)) {
                        _loadSelectedFriendDailyStats(
                            _selectedFriendUid!, pickedDate);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
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
                            "Daily Log Details",
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Divider(),
                          _isLoadingSelectedFriendDateStats
                              ? const Center(child: CircularProgressIndicator())
                              : _selectedFriendDateStatsErrorMessage != null
                                  ? Center(
                                      child: Text(
                                        _selectedFriendDateStatsErrorMessage!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.red, fontSize: 14),
                                      ),
                                    )
                                  : _selectedFriendDailyStats != null
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _buildDataRow(
                                                'Steps',
                                                '🦶',
                                                _selectedFriendDailyStats![
                                                            'stepsPerDay']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(
                                                    TrendType.steps)),
                                            _buildDataRow(
                                                'Worked Out',
                                                '💪',
                                                _selectedFriendDailyStats![
                                                            'workoutsCompleted'] ==
                                                        true
                                                    ? '✔️'
                                                    : '❌',
                                                null),
                                            _buildDataRow(
                                                'Calories Consumed',
                                                '🍔',
                                                _selectedFriendDailyStats![
                                                            'caloriesConsumed']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(TrendType
                                                    .caloriesConsumed)),
                                            _buildDataRow(
                                                'Sleep Hours',
                                                '😴',
                                                _selectedFriendDailyStats![
                                                            'sleepHours']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(
                                                    TrendType.sleepHours)),
                                            _buildDataRow(
                                                'Protein Grams',
                                                '🍗',
                                                _selectedFriendDailyStats![
                                                            'proteinGrams']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(
                                                    TrendType.proteinGrams)),
                                            _buildDataRow(
                                                'Supplements Taken',
                                                '💊',
                                                _selectedFriendDailyStats![
                                                            'supplementsTaken'] ==
                                                        true
                                                    ? '✔️'
                                                    : '❌',
                                                null),
                                            _buildDataRow(
                                                'Water Intake (ml)',
                                                '💧',
                                                _selectedFriendDailyStats![
                                                            'waterIntake']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(
                                                    TrendType.waterIntake)),
                                            _buildDataRow(
                                                'Weight (kg)',
                                                '⚖️',
                                                _selectedFriendDailyStats?[
                                                            'weight']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(
                                                    TrendType.weight)),
                                            _buildDataRow(
                                                'Mood',
                                                '😊',
                                                _selectedFriendDailyStats?[
                                                            'mood']
                                                        ?.toString() ??
                                                    'N/A',
                                                _calculateAverage(
                                                    TrendType.mood)),
                                            _buildDataRow(
                                                'Daily Score',
                                                '',
                                                _selectedFriendDailyStats !=
                                                            null &&
                                                        _selectedFriendDailyStats!
                                                            .containsKey(
                                                                'dailyScore')
                                                    ? (_selectedFriendDailyStats![
                                                                'dailyScore']
                                                            as num)
                                                        .toStringAsFixed(1)
                                                    : 'N/A',
                                                _calculateAverage(
                                                    TrendType.globalScore)),
                                          ],
                                        )
                                      : const Center(
                                          child: Text(
                                            'No data logged for this date.',
                                            style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.grey),
                                          ),
                                        ),
                        ],
                      ),
                    ),
                  ),
                  if (_isLoadingFriendWeeklyScore)
                    const Center(child: CircularProgressIndicator())
                  else if (_friendWeeklyScore != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            "${_selectedFriendDisplayName ?? 'Friend'}'s Weekly Score 7️⃣",
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          ScoreCard(weeklyScore: _friendWeeklyScore!),
                        ],
                      ),
                    )
                  else
                    const Text(
                      "No weekly score for this friend yet.",
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 20),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String emoji, String value,
      [String? averageValue]) {
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (averageValue != null && averageValue != 'N/A')
                Text(
                  'Avg: $averageValue',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendTrendContent() {
    if (_friendDailyLogsData.every((data) => data['isLogged'] == false)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            '${_selectedFriendDisplayName ?? 'This friend'} has no logged data for the last 30 days to show trends. They need to start logging!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    if (_selectedFriendTrend == TrendType.workedOut ||
        _selectedFriendTrend == TrendType.supplementsTaken) {
      return _buildFriendBooleanTrendSummary();
    } else {
      return _buildFriendNumericalTrendGraph();
    }
  }

  Widget _buildFriendBooleanTrendSummary() {
    int daysTaken = 0;
    int daysLogged = 0;

    for (int i = 0; i < _friendDailyLogsData.length; i++) {
      final data = _friendDailyLogsData[i];
      if (data['isLogged'] == true) {
        daysLogged++;
        final bool? value = data[_selectedFriendTrend.toFirestoreKey()];
        if (value == true) {
          daysTaken++;
        }
      }
    }

    final double percentage =
        daysLogged > 0 ? (daysTaken / daysLogged) * 100 : 0;

    String emoji = _selectedFriendTrend.toEmoji();
    String title = _selectedFriendTrend.toDisplayName();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title Trend $emoji',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            Center(
              child: Column(
                children: [
                  Text(
                    '$daysTaken / $daysLogged days',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This represents the percentage of days ${_selectedFriendDisplayName ?? 'this friend'} has ${title.toLowerCase()} out of the $daysLogged days they logged over the last 30 days.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- THE ONLY MAJOR CHANGE IS HERE: --------
  Widget _buildFriendNumericalTrendGraph() {
    final List<FlSpot> spots = [];
    double currentMaxY = 0;
    double currentMinY = double.infinity;

    String fieldKey = _selectedFriendTrend.toFirestoreKey();
    if (_selectedFriendTrend == TrendType.globalScore) {
      fieldKey = 'globalScore';
    }

    // Skip days with value == 0 (only for numerical trends)
    List<Map<String, dynamic>> loggedData = [];
    for (var data in _friendDailyLogsData) {
      if (data['isLogged'] == true) {
        final value = (data[fieldKey] as num?)?.toDouble() ?? 0.0;
        if (value > 0) {
          loggedData.add(data);
        }
      }
    }

    if (loggedData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'No logged data for this trend yet for this friend. Tell them to start tracking!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    for (int i = 0; i < loggedData.length; i++) {
      final data = loggedData[i];
      final value = (data[fieldKey] as num?)?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), value));
      if (value > currentMaxY) currentMaxY = value;
      if (value < currentMinY) currentMinY = value;
    }

    _minY = currentMinY == double.infinity
        ? 0
        : (currentMinY * 0.9).floorToDouble();
    if (_minY < 0 && _selectedFriendTrend != TrendType.caloriesConsumed)
      _minY = 0;
    _maxY = (currentMaxY * 1.1).ceilToDouble();
    if (_maxY == 0) _maxY = 100;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_selectedFriendTrend.toDisplayName()} Trend',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (_selectedFriendTrend != TrendType.workedOut &&
                _selectedFriendTrend != TrendType.supplementsTaken)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  'Average: ${_calculateAverage(_selectedFriendTrend)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            const Divider(height: 20),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    getDrawingHorizontalLine: (value) {
                      return const FlLine(
                        color: Color(0xff37434d),
                        strokeWidth: 0.5,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return const FlLine(
                        color: Color(0xff37434d),
                        strokeWidth: 0.5,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < 0 ||
                              value.toInt() >= loggedData.length)
                            return const Text('');

                          final dateString =
                              loggedData[value.toInt()]['dateId'];
                          final date = DateTime.parse(dateString);
                          final formattedDate =
                              DateFormat('MM/dd').format(date);

                          if (loggedData.length <= 5) {
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              space: 8.0,
                              child: Text(
                                formattedDate,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 10),
                              ),
                            );
                          } else {
                            final int interval = (loggedData.length / 5).ceil();
                            if (value.toInt() % interval == 0) {
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 8.0,
                                child: Text(
                                  formattedDate,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontSize: 10),
                                ),
                              );
                            }
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border:
                        Border.all(color: const Color(0xff37434d), width: 1),
                  ),
                  minX: 0,
                  maxX: (loggedData.length - 1).toDouble(),
                  minY: _minY,
                  maxY: _maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.tertiary,
                        ],
                      ),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: Theme.of(context).colorScheme.secondary,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3),
                            Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withOpacity(0.3),
                          ],
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) {
                        return Theme.of(context).colorScheme.inverseSurface;
                      },
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((LineBarSpot touchedSpot) {
                          final originalDateIndex = touchedSpot.x.toInt();
                          if (originalDateIndex < 0 ||
                              originalDateIndex >= loggedData.length)
                            return null;

                          final dateString =
                              loggedData[originalDateIndex]['dateId'];
                          final date = DateTime.parse(dateString);
                          final formattedDate =
                              DateFormat('MM/dd').format(date);

                          final value = touchedSpot.y.toStringAsFixed(
                              _selectedFriendTrend == TrendType.sleepHours ||
                                      _selectedFriendTrend ==
                                          TrendType.globalScore ||
                                      _selectedFriendTrend ==
                                          TrendType.weight ||
                                      _selectedFriendTrend == TrendType.mood
                                  ? 1
                                  : 0);
                          return LineTooltipItem(
                            '$formattedDate\n$value',
                            TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onInverseSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                    handleBuiltInTouches: true,
                    getTouchedSpotIndicator: (barData, spotIndexes) {
                      return spotIndexes.map((index) {
                        return TouchedSpotIndicatorData(
                          FlLine(
                              color: Theme.of(context).colorScheme.tertiary,
                              strokeWidth: 2),
                          FlDotData(
                            getDotPainter: (spot, percent, bar, index) =>
                                FlDotCirclePainter(
                              radius: 6,
                              color: Theme.of(context).colorScheme.secondary,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            ),
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
