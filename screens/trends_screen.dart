// lib/screens/trends_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fit_index/utils/enums.dart'; // Make sure this path is correct
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TrendType _selectedTrend = TrendType.steps;
  List<Map<String, dynamic>> _dailyLogsData = [];
  bool _isLoadingTrends = true;
  String? _trendErrorMessage;

  double _minY = 0;
  double _maxY = 0;

  DateTime _selectedDateForStats = DateTime.now();
  Map<String, dynamic>? _selectedDateStats;
  bool _isLoadingSelectedDateStats = true;
  String? _selectedDateStatsErrorMessage;
  double _myGlobalScore = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchTrendData();
    _loadSelectedDateStats(_selectedDateForStats);
  }

  String _getDateId(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  Future<void> _loadSelectedDateStats(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingSelectedDateStats = false;
        _selectedDateStats = null;
        _selectedDateStatsErrorMessage = 'Please log in to view daily stats.';
      });
      return;
    }

    setState(() {
      _isLoadingSelectedDateStats = true;
      _selectedDateForStats = date;
      _selectedDateStatsErrorMessage = null;
    });
    try {
      final docId = _getDateId(date);
      final dailyDocSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('daily_logs')
          .doc(docId)
          .get();
      Map<String, dynamic>? fetchedStats = dailyDocSnapshot.data();

      if (fetchedStats != null) {
        fetchedStats['globalScore'] =
            (fetchedStats['dailyScore'] as num?)?.toDouble() ?? 0.0;
      }

      setState(() {
        _selectedDateStats = fetchedStats;
      });
    } catch (e) {
      print('DEBUG: Error loading selected date stats: $e');
      setState(() {
        _selectedDateStats = null;
        _selectedDateStatsErrorMessage = 'Error loading stats: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoadingSelectedDateStats = false;
      });
    }
  }

  Future<void> _fetchTrendData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _trendErrorMessage = 'Please log in to view trends.';
        _isLoadingTrends = false;
      });
      return;
    }

    setState(() {
      _isLoadingTrends = true;
      _trendErrorMessage = null;
      _dailyLogsData = [];
    });
    try {
      final now = DateTime.now();
      final List<String> last30Days = List.generate(
          30, (index) => _getDateId(now.subtract(Duration(days: 29 - index))));
      final dailyLogsCollection =
          _firestore.collection('users').doc(user.uid).collection('daily_logs');

      List<Map<String, dynamic>> fetchedData = [];
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        _myGlobalScore =
            (userDoc.data()!['globalRankScore'] as num?)?.toDouble() ?? 0.0;
      } else {
        _myGlobalScore = 0.0;
      }

      for (String dateId in last30Days) {
        final doc = await dailyLogsCollection.doc(dateId).get();
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          data['dateId'] = dateId;
          data['isLogged'] = true;
          data['globalScore'] = (data['dailyScore'] as num?)?.toDouble() ?? 0.0;
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
            'globalScore': 0.0,
            'mood': 0,
            'weight': 0.0,
          });
        }
      }

      setState(() {
        _dailyLogsData = fetchedData;
        _isLoadingTrends = false;
      });
    } catch (e) {
      print('DEBUG: Error fetching trend data: $e');
      setState(() {
        _trendErrorMessage = 'Error loading data: ${e.toString()}';
        _isLoadingTrends = false;
      });
    }
  }

  String _calculateAverage(TrendType trendType) {
    if (trendType == TrendType.workedOut ||
        trendType == TrendType.supplementsTaken) {
      return 'N/A';
    }

    if (_dailyLogsData.isEmpty) return 'N/A';
    double total = 0;
    int count = 0;
    String fieldKey = trendType.toFirestoreKey();
    if (trendType == TrendType.globalScore) fieldKey = 'globalScore';

    for (var data in _dailyLogsData) {
      if (data['isLogged'] == true) {
        final value = _parseNum(data[fieldKey]);
        // Only include if value > 0
        if (value > 0) {
          total += value;
          count++;
        }
      }
    }

    if (count == 0) return 'N/A';

    if (trendType == TrendType.sleepHours ||
        trendType == TrendType.globalScore ||
        trendType == TrendType.weight) {
      return (total / count).toStringAsFixed(1);
    } else if (trendType == TrendType.mood) {
      return (total / count).toStringAsFixed(1);
    }
    return (total / count).toStringAsFixed(0);
  }

  String _moodEmoji(num? mood) {
    if (mood == null) return 'N/A';
    int m = mood is int ? mood : mood.round();
    switch (m) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trends'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TrendType>(
                    value: _selectedTrend,
                    icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                    isExpanded: true,
                    onChanged: (TrendType? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedTrend = newValue;
                        });
                      }
                    },
                    items: TrendType.values
                        .map<DropdownMenuItem<TrendType>>((TrendType value) {
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
                                  fontSize: 16, fontWeight: FontWeight.w500),
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
            _isLoadingTrends
                ? const Center(child: CircularProgressIndicator())
                : _trendErrorMessage != null
                    ? Center(
                        child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          _trendErrorMessage!,
                          textAlign: TextAlign.center,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 16),
                        ),
                      ))
                    : _buildTrendContent(),
            const SizedBox(height: 40),
            Text(
              'Stats for Selected Day ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextFormField(
              readOnly: true,
              controller: TextEditingController(
                  text: DateFormat('EEEE, MMM d,yyyy')
                      .format(_selectedDateForStats)),
              decoration: InputDecoration(
                labelText: 'Select Date',
                suffixIcon: Icon(Icons.calendar_today,
                    color: Theme.of(context).colorScheme.primary),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceVariant
                    .withOpacity(0.2),
              ),
              onTap: () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: _selectedDateForStats,
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
                          onPrimary: Theme.of(context).colorScheme.onPrimary,
                          onSurface: Theme.of(context).colorScheme.onSurface,
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
                    (pickedDate.day != _selectedDateForStats.day ||
                        pickedDate.month != _selectedDateForStats.month ||
                        pickedDate.year != _selectedDateForStats.year)) {
                  _loadSelectedDateStats(pickedDate);
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
                      "Daily Log Details ",
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    _isLoadingSelectedDateStats
                        ? const Center(child: CircularProgressIndicator())
                        : _selectedDateStatsErrorMessage != null
                            ? Center(
                                child: Text(
                                  _selectedDateStatsErrorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 14),
                                ),
                              )
                            : _selectedDateStats != null
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildDataRow(
                                        'Steps',
                                        '',
                                        _selectedDateStats!['stepsPerDay']
                                                ?.toString() ??
                                            'N/A',
                                        _calculateAverage(TrendType.steps),
                                      ),
                                      _buildDataRow(
                                        'Worked Out',
                                        '',
                                        _selectedDateStats![
                                                    'workoutsCompleted'] ==
                                                true
                                            ? 'Yes'
                                            : 'No',
                                        null,
                                      ),
                                      _buildDataRow(
                                        'Calories Consumed',
                                        '',
                                        _selectedDateStats!['caloriesConsumed']
                                                ?.toString() ??
                                            'N/A',
                                        _calculateAverage(
                                            TrendType.caloriesConsumed),
                                      ),
                                      _buildDataRow(
                                        'Sleep Hours',
                                        '',
                                        _selectedDateStats!['sleepHours']
                                                ?.toString() ??
                                            'N/A',
                                        _calculateAverage(TrendType.sleepHours),
                                      ),
                                      _buildDataRow(
                                        'Protein Grams',
                                        '',
                                        _selectedDateStats!['proteinGrams']
                                                ?.toString() ??
                                            'N/A',
                                        _calculateAverage(
                                            TrendType.proteinGrams),
                                      ),
                                      _buildDataRow(
                                        'Supplements Taken',
                                        '',
                                        _selectedDateStats![
                                                    'supplementsTaken'] ==
                                                true
                                            ? 'Yes'
                                            : 'No',
                                        null,
                                      ),
                                      _buildDataRow(
                                        'Water Intake (ml)',
                                        '',
                                        _selectedDateStats!['waterIntake']
                                                ?.toString() ??
                                            'N/A',
                                        _calculateAverage(
                                            TrendType.waterIntake),
                                      ),
                                      _buildDataRow(
                                        'Weight',
                                        '',
                                        _selectedDateStats!['weight'] != null &&
                                                _parseNum(_selectedDateStats![
                                                        'weight']) >
                                                    0
                                            ? _parseNum(_selectedDateStats![
                                                        'weight'])
                                                    .toStringAsFixed(1) +
                                                ' kg'
                                            : 'N/A',
                                        _calculateAverage(TrendType.weight),
                                      ),
                                      _buildDataRow(
                                        'Mood',
                                        '',
                                        _selectedDateStats!['mood'] != null &&
                                                _parseNum(_selectedDateStats![
                                                        'mood']) >
                                                    0
                                            ? _moodEmoji(_parseNum(
                                                _selectedDateStats!['mood']))
                                            : 'N/A',
                                        _calculateAverage(TrendType.mood),
                                      ),
                                      _buildDataRow(
                                        'Daily Score',
                                        '',
                                        _selectedDateStats != null &&
                                                _selectedDateStats!
                                                    .containsKey('globalScore')
                                            ? (_selectedDateStats![
                                                    'globalScore'] as num)
                                                .toStringAsFixed(1)
                                            : 'N/A',
                                        _calculateAverage(
                                            TrendType.globalScore),
                                      ),
                                    ],
                                  )
                                : const Center(
                                    child: Text(
                                      'No data logged for this date.',
                                      style: TextStyle(
                                          fontSize: 16, color: Colors.grey),
                                    ),
                                  ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
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

  Widget _buildTrendContent() {
    if (_dailyLogsData.every((data) => data['isLogged'] == false)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'No logged data for the last 30 days to show trends. Start logging!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    if (_selectedTrend == TrendType.workedOut ||
        _selectedTrend == TrendType.supplementsTaken) {
      return _buildBooleanTrendSummary();
    } else {
      return _buildNumericalTrendGraph();
    }
  }

  Widget _buildBooleanTrendSummary() {
    int daysTaken = 0;
    int daysLogged = 0;
    for (int i = 0; i < _dailyLogsData.length; i++) {
      final data = _dailyLogsData[i];
      if (data['isLogged'] == true) {
        daysLogged++;
        final bool? value = data[_selectedTrend.toFirestoreKey()];
        if (value == true) {
          daysTaken++;
        }
      }
    }

    final double percentage =
        daysLogged > 0 ? (daysTaken / daysLogged) * 100 : 0;

    String emoji = _selectedTrend.toEmoji();
    String title = _selectedTrend.toDisplayName();
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
                    'This represents the percentage of days you have ${title.toLowerCase()} out of the $daysLogged days you logged over the last 30 days.',
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

  Widget _buildNumericalTrendGraph() {
    final List<FlSpot> spots = [];
    double currentMaxY = 0;
    double currentMinY = double.infinity;

    List<Map<String, dynamic>> loggedData = [];
    String fieldKey = _selectedTrend.toFirestoreKey();
    if (_selectedTrend == TrendType.globalScore) fieldKey = 'globalScore';

    // Skip days where the value is 0 or less
    for (var data in _dailyLogsData) {
      if (data['isLogged'] == true) {
        final value = _parseNum(data[fieldKey]);
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
            'No logged data for this trend yet. Start tracking!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // Add FlSpot only for nonzero entries, x is contiguous
    for (int i = 0; i < loggedData.length; i++) {
      final data = loggedData[i];
      final value = _parseNum(data[fieldKey]);
      spots.add(FlSpot(i.toDouble(), value));
      if (value > currentMaxY) currentMaxY = value;
      if (value < currentMinY) currentMinY = value;
    }

    _minY = currentMinY == double.infinity
        ? 0
        : (currentMinY * 0.9).floorToDouble();
    if (_selectedTrend == TrendType.globalScore) {
      _minY = currentMinY.floorToDouble();
      if (_minY > 0) _minY = 0;
    } else {
      if (_minY < 0) _minY = 0;
    }

    _maxY = (currentMaxY * 1.1).ceilToDouble();
    if (_maxY == 0) {
      _maxY = _selectedTrend == TrendType.globalScore ? 100 : 100;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_selectedTrend.toDisplayName()} Trend',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (_selectedTrend != TrendType.workedOut &&
                _selectedTrend != TrendType.supplementsTaken)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  'Average: ${_calculateAverage(_selectedTrend)}',
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

                          final value = _selectedTrend == TrendType.mood
                              ? _moodEmoji(touchedSpot.y)
                              : _selectedTrend == TrendType.weight
                                  ? '${touchedSpot.y.toStringAsFixed(1)} kg'
                                  : touchedSpot.y.toStringAsFixed(
                                      _selectedTrend == TrendType.sleepHours ||
                                              _selectedTrend ==
                                                  TrendType.globalScore
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
