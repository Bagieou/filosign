import 'package:flutter/material.dart';
import 'learn_repository.dart';
import 'category.dart';
import 'lesson_player_screen.dart';
import 'lesson_progress.dart';
import 'learn_routes.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String categoryId;
  const CategoryDetailScreen({super.key, required this.categoryId});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late final Future<LearnCategory> _future =
      LearnRepository.instance.getCategory(widget.categoryId);
  final _progress = LessonProgress.instance;

  @override
  void initState() {
    super.initState();
    _progress.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _open(LearnCategory cat, int index) async {
    final result = await Navigator.push<QuizResult>(
      context,
      MaterialPageRoute<QuizResult>(
        builder: (_) => LessonPlayerScreen(
          lessons: cat.sortedLessons,
          initialIndex: index,
          category: cat,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {}); // ticks and locks changed while the lesson was open
  }

  void _lockedHint() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Finish the lessons above first, in order.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF087F73),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<LearnCategory>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cat = snap.data!;
          final lessons = cat.sortedLessons;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                  child: Row(
                    children: [
                      Icon(cat.icon, color: const Color(0xFF087F73), size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cat.title,
                          style: const TextStyle(
                            color: Color(0xFF153B39),
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                sliver: SliverList.separated(
                  itemCount: lessons.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFE2EEEB)),
                  itemBuilder: (context, index) {
                    final lesson = lessons[index];
                    final open = _progress.isOpen(lessons, index);
                    final done = _progress.completed(lesson);
                    final retry = _progress.enforced && _progress.watched(lesson) && !done;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 0),
                      title: Text(
                        lesson.title,
                        style: TextStyle(
                          color: open ? const Color(0xFF153B39) : Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: retry
                          ? const Text('Sign not passed yet. Try it again.',
                              style: TextStyle(color: Color(0xFFB26A00), fontSize: 12))
                          : null,
                      trailing: !_progress.enforced
                          ? null
                          : Icon(
                              done
                                  ? Icons.check_circle_rounded
                                  : retry
                                      ? Icons.error_outline_rounded
                                      : open
                                          ? Icons.play_circle_outline_rounded
                                          : Icons.lock_outline_rounded,
                              color: done
                                  ? const Color(0xFF2E9E5B)
                                  : retry
                                      ? const Color(0xFFB26A00)
                                      : open
                                          ? const Color(0xFF087F73)
                                          : Colors.grey,
                            ),
                      onTap: open ? () => _open(cat, index) : _lockedHint,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
