// lib/utils/enums.dart
enum TrendType {
  steps,
  caloriesConsumed,
  sleepHours,
  proteinGrams,
  workedOut,
  supplementsTaken,
  waterIntake,
  globalScore, // NEW ENUM VALUE
  mood, // <--- Add this
  weight,
}

extension TrendTypeExtension on TrendType {
  String toDisplayName() {
    switch (this) {
      case TrendType.steps:
        return 'Steps';
      case TrendType.caloriesConsumed:
        return 'Calories Consumed';
      case TrendType.sleepHours:
        return 'Sleep Hours';
      case TrendType.proteinGrams:
        return 'Protein Grams';
      case TrendType.workedOut:
        return 'Worked Out';
      case TrendType.supplementsTaken:
        return 'Supplements Taken';
      case TrendType.waterIntake:
        return 'Water Intake';
      case TrendType.globalScore: // NEW CASE
        return 'Global Score';
      case TrendType.mood:
        return 'Mood'; // <---
      case TrendType.weight:
        return 'Weight'; // <---
      default:
        return toString().split('.').last;
    }
  }

  String toFirestoreKey() {
    switch (this) {
      case TrendType.steps:
        return 'stepsPerDay';
      case TrendType.caloriesConsumed:
        return 'caloriesConsumed';
      case TrendType.sleepHours:
        return 'sleepHours';
      case TrendType.proteinGrams:
        return 'proteinGrams';
      case TrendType.workedOut:
        return 'workoutsCompleted'; // Matches Firestore field
      case TrendType.supplementsTaken:
        return 'supplementsTaken';
      case TrendType.waterIntake:
        return 'waterIntake';
      case TrendType.mood:
        return 'mood'; // <---
      case TrendType.weight:
        return 'weight'; // <---
      case TrendType
            .globalScore: // NEW CASE: This will be handled differently, as it's not a direct Firestore field
        return 'globalScore'; // Used as an internal key for the added data
      default:
        return '';
    }
  }

  // NEW: Add this toEmoji() method
  String toEmoji() {
    switch (this) {
      case TrendType.steps:
        return '👟'; // Running shoe
      case TrendType.caloriesConsumed:
        return '🍔'; // Hamburger
      case TrendType.sleepHours:
        return '😴'; // Sleeping face
      case TrendType.proteinGrams:
        return '🍗'; // Cooked poultry leg
      case TrendType.workedOut:
        return '💪'; // Flexed biceps
      case TrendType.supplementsTaken:
        return '💊'; // Pill
      case TrendType.waterIntake:
        return '💧'; // Droplet
      case TrendType.globalScore:
        return '✨'; // Sparkles
      case TrendType.mood:
        return '🙂'; // <---
      case TrendType.weight:
        return '⚖️';
    }
  }
}

enum CalorieGoalType {
  maintenance,
  deficit,
  surplus,
}
