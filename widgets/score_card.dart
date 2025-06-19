import 'package:flutter/material.dart';

import '../models/weekly_score.dart';

class ScoreCard extends StatelessWidget {
  final WeeklyScore weeklyScore;

  const ScoreCard({super.key, required this.weeklyScore});

  static const List<_RankStop> rankStops = [
    _RankStop('Wood', '🪵', 0),
    _RankStop('Iron', '⛓️', 500),
    _RankStop('Bronze', '🥉', 1000),
    _RankStop('Silver', '🥈', 1500),
    _RankStop('Gold', '🥇', 2200),
    _RankStop('Platinum', '🌟', 2800),
    _RankStop('Diamond', '💎', 3200),
    _RankStop('Apex Predator', '🦅', 3500),
  ];

  int getCurrentRankIndex(int score) {
    for (int i = rankStops.length - 1; i >= 0; i--) {
      if (score >= rankStops[i].score) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final int score = weeklyScore.finalScore;
    final int rankIndex = getCurrentRankIndex(score);
    final double progress = (score / 3600.0).clamp(0, 1);
    final bool showFire = progress >= 0.8;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: label & score at right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    "Weekly Score",
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      "$score pts",
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                    ),
                    if (showFire)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Text("🔥", style: TextStyle(fontSize: 20)),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Rank (under label)
            Text(
              "${rankStops[rankIndex].emoji} Rank: ${rankStops[rankIndex].label}",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            // Main progress bar (always fits)
            // LinearProgressIndicator is fine as it takes its minHeight.
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.secondary,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 8),
            // RANKS BAR
            _buildRankStopsBar(context, score, rankIndex),
            const Divider(height: 22, thickness: 1),
            Text(
              "Score Breakdown",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            _buildBreakdown("🥗 Nutrition", weeklyScore.nutritionScore, 800),
            _buildBreakdown("👟 Steps", weeklyScore.stepsScore, 600),
            _buildBreakdown("🏋️ Workouts", weeklyScore.workoutScore, 600),
            _buildBreakdown("💊 Supplements", weeklyScore.supplementScore, 100),
            _buildBreakdown("😴 Recovery", weeklyScore.recoveryScore, 400),
            _buildBreakdown("💧 Hydration", weeklyScore.hydrationScore, 500),
            _buildBreakdown("🔥 Streak Bonus", weeklyScore.streakBonus, 600),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildRankStopsBar(
      BuildContext context, int userScore, int rankIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(rankStops.length, (i) {
          final stop = rankStops[i];
          final bool isCurrent = i == rankIndex;
          return Expanded(
            child: Column(
              children: [
                Text(
                  stop.emoji,
                  style: TextStyle(
                    fontSize: isCurrent ? 22 : 16,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[700],
                    shadows: isCurrent
                        ? [
                            Shadow(
                              color: Theme.of(context).colorScheme.secondary,
                              blurRadius: 3,
                            )
                          ]
                        : [],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  stop.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isCurrent ? 11 : 9,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[600],
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                Text(
                  "${stop.score}",
                  style: TextStyle(
                    fontSize: 8,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBreakdown(String label, int value, int max) {
    final double progress = (value / max).clamp(0.0, 1.0);
    final bool isOverachiever = progress >= 0.8;
    final bool isUnderachiever = progress < 0.70;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child:
                Text(label.split(' ')[0], style: const TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 4,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 0.75
                    ? Colors.green
                    : progress >= 0.5
                        ? Colors.orange
                        : Colors.red,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          // FIX: Wrapped the value/emoji SizedBox with FittedBox
          SizedBox(
            width: 40,
            child: FittedBox(
              fit: BoxFit.scaleDown, // Scales down the content if it's too big
              alignment:
                  Alignment.centerRight, // Keeps content aligned to the right
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    "$value",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (isOverachiever)
                    const Text("🔥", style: TextStyle(fontSize: 12))
                  else if (isUnderachiever)
                    const Text("😭", style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankStop {
  final String label;
  final String emoji;
  final int score;
  const _RankStop(this.label, this.emoji, this.score);
}
