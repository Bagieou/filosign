import 'package:flutter/material.dart';

import '../../learn/learn_repository.dart';
import '../practice/live_practice_screen.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = _categories;

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBFA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                child: Text(
                  'Practice',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: const Color(0xFF153B39),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _CategoryTile(category: categories[i]),
                  childCount: categories.length,
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

class _PracticeCategory {
  final String id; // Learn category id (assets/learn/<id>.json)
  final String title;
  final IconData icon;
  final int totalItems;

  const _PracticeCategory(this.id, this.title, this.icon, this.totalItems);
}

const List<_PracticeCategory> _categories = [
  _PracticeCategory('basic', 'Basics', Icons.people_outline, 5),
  _PracticeCategory('letters', 'Letters', Icons.abc_outlined, 26),
  _PracticeCategory('numbers', 'Numbers', Icons.numbers_outlined, 10),
  _PracticeCategory('days', 'Days', Icons.calendar_today_outlined, 10),
  _PracticeCategory('months', 'Months', Icons.date_range_outlined, 12),
  _PracticeCategory('colors', 'Colors', Icons.palette_outlined, 13),
  _PracticeCategory('greetings', 'Greetings', Icons.waving_hand_outlined, 10),
  _PracticeCategory('family', 'Family', Icons.family_restroom_outlined, 15),
  _PracticeCategory('food', 'Food', Icons.restaurant_outlined, 10),
  _PracticeCategory('drinks', 'Drinks', Icons.local_drink_outlined, 10),
  _PracticeCategory('communication', 'Communication', Icons.emergency_outlined, 10),
];

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final _PracticeCategory category;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final learn = await LearnRepository.instance.getCategory(category.id);
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LivePracticeScreen(category: learn)),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2EEEB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14087F73),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(category.icon, size: 36, color: const Color(0xFF087F73)),
              const SizedBox(height: 10),
              Text(
                category.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF153B39),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${category.totalItems} signs',
                style: const TextStyle(
                  color: Color(0xFF6B8581),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}