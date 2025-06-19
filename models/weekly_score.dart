import '../utils/enums.dart';

class WeeklyScore {
  final List<int> stepsPerDay; // Length 7
  final List<bool> workoutsCompleted; // Length 7
  final List<int> caloriesConsumed; // Now actual calories consumed
  final List<double> sleepHours; // Length 7
  final List<int> proteinGrams; // Actual daily protein grams
  final List<bool> supplementsTaken; // Length 7
  final List<int> waterIntake; // Length 7, in ml
  // User's overall calorie target and type
  final int calorieGoal;
  final CalorieGoalType calorieGoalType;
  final int proteinTarget; // Weekly protein target per day (existing)
  final int stepGoal; // Added to constructor
  final int waterGoal; // Added to constructor
  final double sleepTarget; // Added to constructor
  final int workoutGoal; // Added to constructor

  WeeklyScore({
    required this.stepsPerDay,
    required this.workoutsCompleted,
    required this.caloriesConsumed,
    required this.sleepHours,
    required this.proteinGrams,
    required this.supplementsTaken,
    required this.waterIntake,
    required this.calorieGoal,
    required this.calorieGoalType,
    required this.proteinTarget,
    required this.stepGoal, // Added to constructor
    required this.waterGoal, // Added to constructor
    required this.sleepTarget, // Added to constructor
    required this.workoutGoal, // Added to constructor
  });

  // Helper to get a percentage between 0 and 1 for a metric
  // If target is 0, it generally means no goal, so 0 adherence to goal.
  double _getMetricPercentage(double actual, double target) {
    if (target <= 0) {
      return 0.0;
    }
    double percentage = actual / target;
    return percentage.clamp(0.0, 1.0); // Clamp between 0 and 1
  }

  // --- Daily Score Calculation Helpers ---
  // These constants define the maximum possible points for each category per day.
  static const double _maxDailyNutritionPoints = 800 / 7;
  static const double _maxDailyStepsPoints = 600 / 7;
  static const double _maxDailyWorkoutPoints = 600 / 7;
  static const double _maxDailySupplementPoints = 100 / 7;
  static const double _maxDailyRecoveryPoints = 400 / 7;
  static const double _maxDailyHydrationPoints = 500 / 7;

  double _getDailyNutritionPoints(int dayIndex) {
    double dailyScore = 0.0;
    final int loggedCalories = caloriesConsumed[dayIndex];
    final int proteinGramsToday = proteinGrams[dayIndex];

    // Protein score (half of daily nutrition points)
    if (proteinTarget > 0) {
      dailyScore += _getMetricPercentage(
              proteinGramsToday.toDouble(), proteinTarget.toDouble()) *
          (_maxDailyNutritionPoints / 2);
    } else if (proteinGramsToday > 0) {
      // If no protein target but protein was consumed, give half points of this half
      dailyScore += (_maxDailyNutritionPoints / 4);
    }

    // Calorie score (half of daily nutrition points)
    if (loggedCalories <= 100) {
      // No points if logged calories are 100 or less
      // dailyScore remains unchanged for calories part for this condition
    } else if (calorieGoal > 0) {
      // Use 20% of calorieGoal as the tolerance for full points for streak
      final double calorieTolerance = calorieGoal * 0.20;
      double caloriePoints = 0.0;
      const double maxCaloriePointsForDay = _maxDailyNutritionPoints / 2;
      // Define a point beyond which score is 0. This should be greater than calorieTolerance.
      const double zeroPointsThresholdAbsolute =
          1000.0; // Example: 1000kcal deviation for 0 points

      switch (calorieGoalType) {
        case CalorieGoalType.maintenance:
          final double absoluteDelta =
              (loggedCalories - calorieGoal).abs().toDouble();
          if (absoluteDelta <= calorieTolerance) {
            caloriePoints = maxCaloriePointsForDay;
          } else {
            double effectiveDeviation = absoluteDelta - calorieTolerance;
            double decayFactor = effectiveDeviation /
                (zeroPointsThresholdAbsolute - calorieTolerance);
            if (decayFactor.isNaN || decayFactor.isInfinite)
              decayFactor = 1.0; // Handle division by zero/infinity
            if (decayFactor > 1.0) decayFactor = 1.0;
            caloriePoints = maxCaloriePointsForDay * (1.0 - decayFactor);
          }
          break;
        case CalorieGoalType.deficit:
          // For deficit, penalize if going over goal + tolerance
          if (loggedCalories <= calorieGoal + calorieTolerance) {
            caloriePoints = maxCaloriePointsForDay;
          } else {
            double overshoot =
                loggedCalories - (calorieGoal + calorieTolerance);
            double decayFactor =
                overshoot / (zeroPointsThresholdAbsolute - calorieTolerance);
            if (decayFactor.isNaN || decayFactor.isInfinite) decayFactor = 1.0;
            if (decayFactor > 1.0) decayFactor = 1.0;
            caloriePoints = maxCaloriePointsForDay * (1.0 - decayFactor);
          }
          break;
        case CalorieGoalType.surplus:
          // For surplus, penalize if going under goal - tolerance
          if (loggedCalories >= calorieGoal - calorieTolerance) {
            caloriePoints = maxCaloriePointsForDay;
          } else {
            double undershoot =
                (calorieGoal - calorieTolerance) - loggedCalories;
            double decayFactor =
                undershoot / (zeroPointsThresholdAbsolute - calorieTolerance);
            if (decayFactor.isNaN || decayFactor.isInfinite) decayFactor = 1.0;
            if (decayFactor > 1.0) decayFactor = 1.0;
            caloriePoints = maxCaloriePointsForDay * (1.0 - decayFactor);
          }
          break;
      }
      dailyScore += caloriePoints.clamp(0.0, maxCaloriePointsForDay);
    } else {
      // If no calorie goal, but logged calories > 100, award some points
      dailyScore += (_maxDailyNutritionPoints / 4);
    }

    return dailyScore;
  }

  double _getDailyStepsPoints(int dayIndex) {
    if (stepGoal > 0) {
      return _getMetricPercentage(
              stepsPerDay[dayIndex].toDouble(), stepGoal.toDouble()) *
          _maxDailyStepsPoints;
    } else {
      // Default to 10000 steps if no step goal is set
      return _getMetricPercentage(stepsPerDay[dayIndex].toDouble(), 10000.0) *
          _maxDailyStepsPoints;
    }
  }

  double _getDailyWorkoutPoints(int dayIndex) {
    // If a workout is completed, assign full daily max points for this category.
    // We treat 'completing a workout' as meeting the daily workout goal for streak.
    if (workoutsCompleted[dayIndex]) {
      // If workoutGoal is set, and a workout is completed, award full points.
      // If no workoutGoal, but a workout is completed, still award points.
      return _maxDailyWorkoutPoints;
    }
    return 0.0;
  }

  double _getDailySupplementPoints(int dayIndex) {
    return supplementsTaken[dayIndex] ? _maxDailySupplementPoints : 0.0;
  }

  double _getDailyRecoveryPoints(int dayIndex) {
    final double sleepToday = sleepHours[dayIndex];
    if (sleepTarget > 0) {
      // Calculate adherence percentage for sleep (closer to 1.0 is better)
      double deviation = (sleepToday - sleepTarget).abs();
      // Max deviation beyond which score drops to 0 (e.g., 2 hours off target)
      const double maxDeviationConsidered = 2.0;
      double adherencePercentage = 1.0 - (deviation / maxDeviationConsidered);
      adherencePercentage = adherencePercentage.clamp(
          0.0, 1.0); // Ensure percentage is between 0 and 1
      return adherencePercentage * _maxDailyRecoveryPoints;
    } else {
      // Default sleep target range (6.5 to 8.5 hours)
      const double idealMin = 6.5;
      const double idealMax = 8.5;
      double deviation = 0.0;
      if (sleepToday < idealMin) {
        deviation = idealMin - sleepToday;
      } else if (sleepToday > idealMax) {
        deviation = sleepToday - idealMax;
      }
      const double defaultMaxDeviationConsidered =
          2.0; // 2 hours off default ideal range gets 0 points
      double adherencePercentage =
          1.0 - (deviation / defaultMaxDeviationConsidered);
      adherencePercentage = adherencePercentage.clamp(0.0, 1.0);
      return adherencePercentage * _maxDailyRecoveryPoints;
    }
  }

  double _getDailyHydrationPoints(int dayIndex) {
    if (waterGoal > 0) {
      return _getMetricPercentage(
              waterIntake[dayIndex].toDouble(), waterGoal.toDouble()) *
          _maxDailyHydrationPoints;
    } else {
      // Default to 3000ml if no water goal is set
      return _getMetricPercentage(waterIntake[dayIndex].toDouble(), 3000.0) *
          _maxDailyHydrationPoints;
    }
  }

  // --- Total Daily Score for Streak Calculation (still exists for potential future use or other score components) ---
  double _getDailyTotalScore(int dayIndex) {
    return (_getDailyNutritionPoints(dayIndex) +
        _getDailyStepsPoints(dayIndex) +
        _getDailyWorkoutPoints(dayIndex) +
        _getDailySupplementPoints(dayIndex) +
        _getDailyRecoveryPoints(dayIndex) +
        _getDailyHydrationPoints(dayIndex));
  }

  // --- Weekly Aggregate Score Getters (summing daily points) ---
  @override
  int get nutritionScore {
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _getDailyNutritionPoints(i);
    }
    if (total > 650) total = total + 2;
    return total.round().clamp(0, 800);
  }

  @override
  int get stepsScore {
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _getDailyStepsPoints(i);
    }
    return total.round().clamp(0, 600);
  }

  @override
  int get workoutScore {
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _getDailyWorkoutPoints(i);
    }
    return total.round().clamp(0, 600);
  }

  @override
  int get supplementScore {
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _getDailySupplementPoints(i);
    }
    if (total > 80) total = total + 2;
    return total.round().clamp(0, 100);
  }

  @override
  int get recoveryScore {
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _getDailyRecoveryPoints(i);
    }
    if (total > 350) total = total + 1;
    return total.round().clamp(0, 400);
  }

  @override
  int get hydrationScore {
    double total = 0;
    for (int i = 0; i < 7; i++) {
      total += _getDailyHydrationPoints(i);
    }
    return total.round().clamp(0, 500);
  }

  // MODIFIED: Streak bonus now based on hitting 70% of individual goals for 3 consecutive days.
  int get streakBonus {
    int streaks = 0;

    // Iterate over 3-day windows (day 0-2, 1-3, 2-4, 3-5, 4-6)
    for (int i = 0; i <= 4; i++) {
      // Ensure we have 3 days to check
      if (i + 2 >= 7) continue;

      bool stepsStreakDay = true;
      bool calorieStreakDay = true;
      bool workoutStreakDay = true;

      for (int j = 0; j < 3; j++) {
        // Check each day in the 3-day window
        int dayIndex = i + j;

        // 1. Steps Check: 70% of stepGoal
        if (stepGoal > 0) {
          if (stepsPerDay[dayIndex] < (stepGoal * 0.7).round()) {
            stepsStreakDay = false;
          }
        } else {
          // Default to 70% of 10000 steps if no goal is set for steps
          if (stepsPerDay[dayIndex] < (10000 * 0.7).round()) {
            stepsStreakDay = false;
          }
        }

        // 2. Calorie Check: > 100 calories logged AND within 30% tolerance of calorieGoal
        final int loggedCalories = caloriesConsumed[dayIndex];
        if (loggedCalories <= 100) {
          calorieStreakDay = false; // Must log more than 100 calories
        } else if (calorieGoal <= 0) {
          // If calorieGoal is not set, calorie streak cannot be achieved for this day
          calorieStreakDay = false;
        } else {
          // 30% of goal as dynamic tolerance for streak
          final double calorieToleranceForStreak = calorieGoal * 0.30;
          final int dailyCaloriesDelta = loggedCalories - calorieGoal;

          switch (calorieGoalType) {
            case CalorieGoalType.maintenance:
              if (dailyCaloriesDelta.abs() > calorieToleranceForStreak) {
                calorieStreakDay = false;
              }
              break;
            case CalorieGoalType.deficit:
              // For deficit, logged calories must be less than or equal to goal + 30% tolerance
              if (loggedCalories > calorieGoal + calorieToleranceForStreak) {
                calorieStreakDay = false;
              }
              break;
            case CalorieGoalType.surplus:
              // For surplus, logged calories must be greater than or equal to goal - 30% tolerance
              if (loggedCalories < calorieGoal - calorieToleranceForStreak) {
                calorieStreakDay = false;
              }
              break;
          }
        }

        // 3. Workout Check: Must have a workoutGoal > 0 AND workout completed
        // If workoutGoal is 0 or less, a workout cannot contribute to streak.
        if (workoutGoal <= 0 || !workoutsCompleted[dayIndex]) {
          workoutStreakDay = false;
        }
      }

      // If all conditions met for the 3-day window, increment streak
      if (stepsStreakDay && calorieStreakDay && workoutStreakDay) {
        streaks += 1;
      }
    }
    // Max streak bonus is 600 points for 5 streaks (120 points per streak)
    return (streaks * (600 ~/ 5)).clamp(0, 600);
  }

  // finalScore is the sum of raw scores, clamped at max 3600
  @override
  int get finalScore {
    final int rawTotalScore = nutritionScore +
        stepsScore +
        workoutScore +
        supplementScore +
        recoveryScore +
        hydrationScore +
        streakBonus;

    const int maxRawScore = 800 + 600 + 600 + 100 + 400 + 500 + 600; // = 3600

    return rawTotalScore.clamp(0, maxRawScore); // Ensure it stays within bounds
  }

  // Rank tiers for the 0-3600 score range
  @override
  String get rank {
    int score = finalScore; // Use the raw finalScore

    if (score >= 3500) return "Apex Predator";
    if (score >= 3200) return "Diamond";
    if (score >= 2800) return "Platinum";
    if (score >= 2200) return "Gold";
    if (score >= 1500) return "Silver";
    if (score >= 1000) return "Bronze";
    if (score >= 500) return "Iron";
    return "Wood";
  }
}
