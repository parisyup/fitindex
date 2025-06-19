import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

const List<String> motivationalQuotes = [
  "Every day is a fresh start.",
  "Progress, not perfection.",
  "Small steps, big changes.",
  "Consistency beats intensity.",
  "You’re stronger than you think.",
  "Never give up on yourself.",
  "Discipline > motivation.",
  "You get what you work for.",
  "One step at a time!",
  "Don’t wish for it, work for it.",
];

String randomQuote() {
  final random = Random();
  return motivationalQuotes[random.nextInt(motivationalQuotes.length)];
}

String supportLine() => "Don’t give up! You’re doing great.";

/// Workmanager background callback for Android.
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Setup for background tasks
    await Firebase.initializeApp();
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await notifications.initialize(initSettings);

    if (task == "evening_reminder") {
      await sendEveningReminder(notifications);
    } else if (task == "morning_motivation") {
      await sendMorningMotivation(notifications);
    }
    return Future.value(true);
  });
}

Future<void> sendEveningReminder(
    FlutterLocalNotificationsPlugin notifications) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final targets = userDoc.data() ?? {};
  final logDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('daily_logs')
      .doc(today)
      .get();

  if (!logDoc.exists) {
    await notifications.show(
      0,
      "Don't forget your FitIndex log!",
      "Log your day to avoid a -25 penalty and reflect on your progress.\n${supportLine()}",
      const NotificationDetails(
        android: AndroidNotificationDetails('daily_reminder', 'Daily Reminder'),
      ),
    );
    return;
  }

  final log = logDoc.data()!;
  List<String> tips = [];

  // Steps
  if (!(log['didntTrackSteps'] ?? false) && (targets['stepGoal'] ?? 0) > 0) {
    if ((log['stepsPerDay'] ?? 0) < targets['stepGoal']) {
      tips.add("Try to walk more steps tomorrow.");
    }
  }
  // Water
  if (!(log['didntTrackWater'] ?? false) && (targets['waterGoal'] ?? 0) > 0) {
    if ((log['waterIntake'] ?? 0) < targets['waterGoal']) {
      tips.add("Remember to drink more water tomorrow.");
    }
  }
  // Protein
  if (!(log['didntTrackProtein'] ?? false) &&
      (targets['proteinTarget'] ?? 0) > 0) {
    if ((log['proteinGrams'] ?? 0) < targets['proteinTarget']) {
      tips.add("Aim to hit your protein goal.");
    }
  }
  // Calories
  if (!(log['didntTrackCalories'] ?? false) &&
      (targets['calorieGoal'] ?? 0) > 0) {
    final int loggedCals = (log['caloriesConsumed'] ?? 0) as int;
    final double goalCals = (targets['calorieGoal'] ?? 0).toDouble();
    if ((loggedCals - goalCals).abs() > goalCals * 0.20) {
      tips.add("Try to stay closer to your calorie target.");
    }
  }
  // Sleep
  if ((targets['sleepTarget'] ?? 0) > 0) {
    double actualSleep = (log['sleepHours'] ?? 0.0) is int
        ? (log['sleepHours'] ?? 0).toDouble()
        : (log['sleepHours'] ?? 0.0);
    double sleepTarget = (targets['sleepTarget'] ?? 8.0).toDouble();
    if ((actualSleep - sleepTarget).abs() > 0.5) {
      tips.add("Try to sleep within 0.5 hours of your target for max points.");
    }
  }
  // Workouts
  if (!(log['workoutsCompleted'] ?? false)) {
    tips.add("Complete your workout tomorrow for extra points.");
  }
  // Supplements
  if (!(log['supplementsTaken'] ?? false)) {
    tips.add("Don’t forget your supplements for bonus points.");
  }
  // Mood
  if ((log['mood'] ?? 3) < 3) {
    tips.add("Try to end your day with something that lifts your mood.");
  }

  String message;
  if (tips.isEmpty) {
    message = "Great job today! Keep it up.\n${supportLine()}";
  } else {
    final random = Random();
    message = "${tips[random.nextInt(tips.length)]}\n${supportLine()}";
  }

  await notifications.show(
    1,
    "FitIndex Quick Review",
    message,
    const NotificationDetails(
      android: AndroidNotificationDetails('review', 'Review'),
    ),
  );
}

Future<void> sendMorningMotivation(
    FlutterLocalNotificationsPlugin notifications) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final yesterday = DateFormat('yyyy-MM-dd')
      .format(DateTime.now().subtract(const Duration(days: 1)));
  final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final targets = userDoc.data() ?? {};
  final logDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('daily_logs')
      .doc(yesterday)
      .get();

  String message;

  if (!logDoc.exists) {
    // User did not log anything yesterday
    message =
        "You didn’t track yesterday. Try to log today and get back on track! Every day is a new start. Don’t give up!";
  } else {
    // User logged yesterday, normal tips/quotes logic
    List<String> tips = [];
    final log = logDoc.data()!;
    if (!(log['didntTrackSteps'] ?? false) && (targets['stepGoal'] ?? 0) > 0) {
      if ((log['stepsPerDay'] ?? 0) < targets['stepGoal']) {
        tips.add("Yesterday you missed your step goal, hit it today!");
      }
    }
    if (!(log['didntTrackWater'] ?? false) && (targets['waterGoal'] ?? 0) > 0) {
      if ((log['waterIntake'] ?? 0) < targets['waterGoal']) {
        tips.add("Hydrate well today!");
      }
    }
    if (!(log['didntTrackProtein'] ?? false) &&
        (targets['proteinTarget'] ?? 0) > 0) {
      if ((log['proteinGrams'] ?? 0) < targets['proteinTarget']) {
        tips.add("Hit your protein target today!");
      }
    }
    if (!(log['didntTrackCalories'] ?? false) &&
        (targets['calorieGoal'] ?? 0) > 0) {
      final int loggedCals = (log['caloriesConsumed'] ?? 0) as int;
      final double goalCals = (targets['calorieGoal'] ?? 0).toDouble();
      if ((loggedCals - goalCals).abs() > goalCals * 0.20) {
        tips.add("Stay closer to your calorie target today.");
      }
    }
    if ((targets['sleepTarget'] ?? 0) > 0) {
      double actualSleep = (log['sleepHours'] ?? 0.0) is int
          ? (log['sleepHours'] ?? 0).toDouble()
          : (log['sleepHours'] ?? 0.0);
      double sleepTarget = (targets['sleepTarget'] ?? 8.0).toDouble();
      if ((actualSleep - sleepTarget).abs() > 0.5) {
        tips.add("Try to hit your sleep target tonight!");
      }
    }
    if (!(log['workoutsCompleted'] ?? false)) {
      tips.add("Complete your workout today!");
    }
    if (!(log['supplementsTaken'] ?? false)) {
      tips.add("Take your supplements today!");
    }
    if ((log['mood'] ?? 3) < 3) {
      tips.add("Do something that puts you in a good mood today.");
    }

    message = randomQuote();
    if (tips.isNotEmpty) {
      final random = Random();
      message += "\n" + tips[random.nextInt(tips.length)];
    }
    message += "\nDon’t give up! You’re doing great.";
  }

  await notifications.show(
    2,
    "FitIndex Motivation",
    message,
    const NotificationDetails(
      android: AndroidNotificationDetails('motivation', 'Morning Motivation'),
    ),
  );
}
