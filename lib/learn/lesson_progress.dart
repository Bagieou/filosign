import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test_build.dart';
import 'lesson.dart';

/// Which lessons the signed-in user has finished, kept on the server
/// (table `lesson_progress`, functions `get_lesson_progress` and
/// `record_lesson`).
///
/// A lesson is *watched* once its video was played to the end and its sign
/// check was tried (passed or skipped): the next lesson then opens. It is
/// *completed* only when the sign check was passed. The progress bar counts
/// completed lessons, and the quiz needs every lesson of the category
/// completed.
class LessonProgress {
  LessonProgress._();
  static final instance = LessonProgress._();

  /// video id -> sign passed
  final Map<int, bool> _rows = {};
  String? _user;

  /// False until the server answered once. While false (older backend
  /// without these functions, or offline) lessons stay open as before
  /// instead of locking everyone out.
  bool _available = false;

  /// Lesson order is enforced only in the normal app; the all-open testing
  /// builds keep every lesson reachable.
  bool get enforced => _available && !kAllOpen;

  static int? videoId(Lesson l) => int.tryParse(
      RegExp(r'(\d+)\.mp4$').firstMatch(l.videoAsset ?? '')?.group(1) ?? '');

  Future<void> refresh() async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (user != _user) {
      _rows.clear();
      _available = false;
      _user = user;
    }
    if (user == null) return;
    try {
      final res = await Supabase.instance.client.rpc('get_lesson_progress');
      _rows.clear();
      if (res is List) {
        for (final r in res) {
          if (r is Map && r['video_id'] is num) {
            _rows[(r['video_id'] as num).toInt()] = r['sign_passed'] == true;
          }
        }
      }
      _available = true;
    } catch (e) {
      debugPrint('get_lesson_progress failed: $e');
    }
  }

  bool watched(Lesson l) => _rows.containsKey(videoId(l));

  bool completed(Lesson l) => _rows[videoId(l)] == true;

  int completedCount(List<Lesson> lessons) => lessons.where(completed).length;

  /// Lessons open in order: the first one, any already watched, and the one
  /// right after the last watched lesson.
  bool isOpen(List<Lesson> lessons, int i) =>
      !enforced || i == 0 || watched(lessons[i]) || watched(lessons[i - 1]);

  /// [wanted] if it is open, otherwise the first lesson not watched yet.
  int openIndex(List<Lesson> lessons, int wanted) {
    if (isOpen(lessons, wanted)) return wanted;
    final i = lessons.indexWhere((l) => !watched(l));
    return i == -1 ? wanted : i;
  }

  /// Lessons whose sign was not passed yet (the quiz waits for these).
  List<Lesson> missing(List<Lesson> lessons) =>
      enforced ? lessons.where((l) => !completed(l)).toList() : const [];

  Future<void> record(Lesson l, {required bool signPassed}) async {
    final id = videoId(l);
    if (id == null) return;
    _rows[id] = (_rows[id] ?? false) || signPassed;
    try {
      await Supabase.instance.client.rpc(
        'record_lesson',
        params: {'p_video_id': id, 'p_sign_passed': signPassed},
      );
    } catch (e) {
      debugPrint('record_lesson failed: $e');
    }
  }
}
