import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fit_index/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/input_for_today.dart';
import 'screens/leaderboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/trends_screen.dart';
import 'utils/background_tasks.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print("🟣 Initializing Firebase...");
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("✅ Firebase initialized");

    // --- Notification Plugin Setup ---
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: android, iOS: ios);

    await notifications.initialize(initSettings);

    // --- iOS permissions ---
    if (Platform.isIOS) {
      await notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    // --- Schedule notifications for iOS ---
    if (Platform.isIOS) {
      tz.initializeTimeZones();
      await notifications.cancelAll(); // Prevent duplicates!

      // Morning (9:00AM)
      await notifications.zonedSchedule(
        100,
        'FitIndex Motivation',
        'Start your day strong! Log your stats and make progress today!',
        _nextInstanceOfHourAndMinute(5, 0),
        const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      // Evening (9:00PM)
      await notifications.zonedSchedule(
        200,
        "FitIndex Quick Review",
        "Don't forget to log your day and reflect on your progress! 💪",
        _nextInstanceOfHourAndMinute(17, 0),
        const NotificationDetails(iOS: DarwinNotificationDetails()),
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }

    // --- Schedule WorkManager for Android ---
    if (Platform.isAndroid) {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      await Workmanager().registerPeriodicTask(
        "evening_task",
        "evening_reminder",
        frequency: const Duration(hours: 24),
        initialDelay: Duration(
          hours: (21 - DateTime.now().hour) % 24,
          minutes: 0,
        ),
        constraints: Constraints(networkType: NetworkType.connected),
      );

      await Workmanager().registerPeriodicTask(
        "morning_task",
        "morning_motivation",
        frequency: const Duration(hours: 24),
        initialDelay: Duration(
          hours: (9 - DateTime.now().hour) % 24,
          minutes: 0,
        ),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }

    runApp(const AuthWrapper());
  } catch (e, stackTrace) {
    print("❌ Firebase init failed: $e");
    print(stackTrace);
    runApp(ErrorApp(error: e.toString()));
  }
}

// Helper for iOS notification scheduling
tz.TZDateTime _nextInstanceOfHourAndMinute(int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasData) {
          return const MyApp(); // User is logged in
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const AuthScreen(), // No user logged in
        );
      },
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    HomeScreen(),
    InputForTodayScreen(),
    LeaderboardScreen(),
    TrendsScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitIndex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: _widgetOptions.elementAt(_selectedIndex),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.edit_note),
              label: 'Input',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard),
              label: 'Leaderboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.trending_up),
              label: 'Trends',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
        ),
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  const ErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              'An error occurred during app initialization:\n\n$error',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
