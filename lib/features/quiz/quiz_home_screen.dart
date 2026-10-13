import 'package:flutter/material.dart';

import '../../learn/learn_repository.dart';
import 'quiz_screen.dart';

/// Pick a category for a 10-question quiz (same tile style as Practice).
class QuizHomeScreen extends StatelessWidget {
  const QuizHomeScreen({super.key});

  static const List<(String, String, IconData)> _categories = [
    ('basic', 'Basics', Icons.people_outline),
    ('letters', 'Letters', Icons.abc_outlined),
    ('numbers', 'Numbers', Icons.numbers_outlined),
    ('days', 'Days', Icons.calendar_today_outlined),
    ('months', 'Months', Icons.date_range_outlined),
    ('colors', 'Colors', Icons.palette_outlined),
    ('greetings', 'Greetings', Icons.waving_hand_outlined),
    ('family', 'Family', Icons.family_restroom_outlined),
    ('food', 'Food', Icons.restaurant_outlined),
    ('drinks', 'Drinks', Icons.local_drink_outlined),
    ('communication', 'Communication', Icons.emergency_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBFA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FBFA),
        foregroundColor: const Color(0xFF153B39),
        elevation: 0,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                child: Text(
                  'Quiz',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: const Color(0xFF153B39),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: Text(
                  '10 questions: sign it on camera or name the sign in the video.',
                  style: TextStyle(color: Color(0xFF6B8581), fontSize: 13),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _QuizTile(
                    id: _categories[i].$1,
                    title: _categories[i].$2,
                    icon: _categories[i].$3,
                  ),
                  childCount: _categories.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _QuizTile extends StatelessWidget {
  final String id, title;
  final IconData icon;
  const _QuizTile({required this.id, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final category = await LearnRepository.instance.getCategory(id);
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => QuizScreen(category: category)),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2EEEB)),
            boxShadow: const [
              BoxShadow(color: Color(0x14087F73), blurRadius: 12, offset: Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: const Color(0xFFE8782F)),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF153B39),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text('10 questions',
                  style: TextStyle(color: Color(0xFF6B8581), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
