import 'package:flutter/material.dart';

import '../learn/learn_routes.dart';

/// Learner progress (manuscript Objective 2 / REQ007): the level, how much of
/// the learning path is done, and the daily streak - one card, shown the same
/// way on Home and Profile.
///
/// Level = categories mastered + 1 (a category is mastered by passing its
/// quiz, which also unlocks the next one), so a new learner starts at Level 1
/// and the bar shows the share of the [kCategoryDbIds.length] categories done.
class ProgressCard extends StatelessWidget {
  /// Categories completed (server `get_lessons_completed`).
  final Future<int> mastered;
  final Future<int> streak;
  const ProgressCard({super.key, required this.mastered, required this.streak});

  static int get totalCategories => kCategoryDbIds.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF087F73), Color(0xFF10A99A), Color(0xFFF18A3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x26087F73), blurRadius: 18, offset: Offset(0, 9)),
        ],
      ),
      child: FutureBuilder<List<int>>(
        future: Future.wait([mastered, streak]),
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final total = totalCategories;
          final done = (snap.data?[0] ?? 0).clamp(0, total);
          final days = snap.data?[1] ?? 0;
          final level = done >= total ? total : done + 1;
          final pct = total == 0 ? 0.0 : done / total;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text('$level',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your progress',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(loading ? 'Level …' : 'Level $level',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  // streak
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 4),
                        Text(loading ? '…' : '$days ${days == 1 ? 'day' : 'days'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: loading ? null : pct,
                  minHeight: 10,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loading ? '' : '$done of $total categories mastered',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(loading ? '' : '${(pct * 100).round()}% complete',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                loading
                    ? ''
                    : done >= total
                        ? 'All categories mastered. Keep your streak going!'
                        : done == total - 1
                            ? 'Pass the last category quiz (70%) to master them all.'
                            : 'Pass a category quiz (70%) to reach Level ${level + 1}.',
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
