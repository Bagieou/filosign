import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:filosign/learn/category_detail_screen.dart';
import 'package:filosign/learn/learn_routes.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  // Order = unlock order. Position passed to the server is index + 1.
  static const List<_LearnCategory> _categories = [
    _LearnCategory('Basics', 'basic', Icons.people_outline, 5),
    _LearnCategory('Letters', 'letters', Icons.abc_outlined, 26),
    _LearnCategory('Numbers', 'numbers', Icons.numbers_outlined, 10),
    _LearnCategory('Days', 'days', Icons.calendar_today_outlined, 10),
    _LearnCategory('Months', 'months', Icons.date_range_outlined, 12),
    _LearnCategory('Colors', 'colors', Icons.palette_outlined, 13),
    _LearnCategory('Greetings', 'greetings', Icons.waving_hand_outlined, 10),
    _LearnCategory('Family', 'family', Icons.family_restroom_outlined, 15),
    _LearnCategory('Food', 'food', Icons.restaurant_outlined, 10),
    _LearnCategory('Drinks', 'drinks', Icons.local_drink_outlined, 10),
    _LearnCategory('Communication', 'communication', Icons.emergency_outlined, 10),
  ];

  // Everything except Basics starts locked until the server says otherwise.
  Map<String, bool> _access = {'basic': true};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = await _fetchAll();
    if (!mounted) return;
    setState(() {
      _access = map;
      _loaded = true;
    });
  }

  Future<Map<String, bool>> _fetchAll() async {
    final results = await Future.wait([
      for (var i = 0; i < _categories.length; i++) _fetchAccess(i + 1),
    ]);
    return {
      for (var i = 0; i < _categories.length; i++) _categories[i].id: results[i],
    };
  }

  Future<bool> _fetchAccess(int position) async {
    if (position == 1) return true; // Basics is always open
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    try {
      final result = await Supabase.instance.client.rpc(
        'can_access_category',
        params: {'p_user': user.id, 'p_category': position},
      );
      return _asBool(result);
    } catch (_) {
      return false; // locked on any error
    }
  }

  static bool _asBool(dynamic r) {
    if (r is bool) return r;
    if (r is List) return r.isNotEmpty && _asBool(r.first);
    if (r is Map) return r.isNotEmpty && _asBool(r.values.first);
    return false;
  }

  Future<void> _openCategory(_LearnCategory c) async {
    // Only diff for unlocks if we knew the state before opening.
    final before = _loaded ? Map<String, bool>.of(_access) : null;

    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kCategoryDetailRoute),
        builder: (_) => CategoryDetailScreen(categoryId: c.id),
      ),
    );
    if (!mounted) return;

    // Back from the category (quiz passed, or the user just went back).
    final after = await _fetchAll();
    if (!mounted) return;
    setState(() {
      _access = after;
      _loaded = true;
    });

    if (before == null) return;
    final newly = _categories
        .where((x) => after[x.id] == true && before[x.id] != true)
        .toList();
    if (newly.isNotEmpty) _showUnlocked(newly.first);
  }

  void _showLockedHint(int index) {
    final prev = _categories[index - 1];
    final c = _categories[index];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
              'Score at least 90% on the ${prev.title} quiz to unlock ${c.title}.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF087F73),
        ),
      );
  }

  void _showUnlocked(_LearnCategory c) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        icon: const Icon(Icons.lock_open_rounded,
            color: Color(0xFF087F73), size: 44),
        title: Text('${c.title} unlocked!',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF153B39), fontWeight: FontWeight.w800)),
        content: Text(
            'Great work! ${c.totalSigns} new signs are ready for you.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B8581))),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openCategory(c);
            },
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFF087F73)),
            child: const Text('Start learning'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBFA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                child: Text(
                  'Start Learning',
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
                  (_, i) {
                    final c = _categories[i];
                    final open = _access[c.id] ?? false;
                    return _CategoryTile(
                      category: c,
                      canAccess: open,
                      onTap: open ? () => _openCategory(c) : () => _showLockedHint(i),
                    );
                  },
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

class _LearnCategory {
  final String title;
  final String id;
  final IconData icon;
  final int totalSigns;

  const _LearnCategory(this.title, this.id, this.icon, this.totalSigns);
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.canAccess,
    required this.onTap,
  });
  final _LearnCategory category;
  final bool canAccess;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: canAccess ? Colors.white : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: canAccess
                    ? const Color(0xFFE2EEEB)
                    : Colors.grey.shade400),
            boxShadow: canAccess
                ? const [
                    BoxShadow(
                      color: Color(0x14087F73),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                canAccess ? category.icon : Icons.lock_outline_rounded,
                size: 36,
                color: canAccess ? const Color(0xFF087F73) : Colors.grey,
              ),
              const SizedBox(height: 10),
              Text(
                category.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: canAccess ? const Color(0xFF153B39) : Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${category.totalSigns} signs',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}