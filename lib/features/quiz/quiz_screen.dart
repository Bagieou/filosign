import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../learn/category.dart';
import '../../learn/lesson.dart';
import '../../recognizer/sign_labels.dart';
import '../practice/live_practice_screen.dart' show FeedbackBanner, Top3Panel;
import '../practice/live_sign_view.dart';
import 'package:filosign/widgets/celebration_overlay.dart';
import 'package:filosign/learn/learn_routes.dart';

const _teal = Color(0xFF087F73);
const _ink = Color(0xFF153B39);
const _muted = Color(0xFF6B8581);
const _bg = Color(0xFFF6FBFA);
const _border = Color(0xFFE2EEEB);

class _Question {
  final Lesson lesson;
  final bool live; // live camera challenge, else video identification
  final List<Lesson> options; // video questions only
  _Question(this.lesson, this.live, this.options);
}

class QuizResult {
  final String categoryId;
  final int score;
  final int total;
  const QuizResult(
      {required this.categoryId, required this.score, required this.total});
  bool get passed => score * 100 >= total * 90;
}

/// 10-question fquiz for one category. Questions randomly mix a Live Camera
/// Challenge (sign it, matched at >= 85% within the time limit) and Video
/// Identification (watch, pick 1 of 4). Green = correct (+1 point),
/// red = incorrect with a reference-video hint pop-up.
class QuizScreen extends StatefulWidget {
  final LearnCategory category;
  final int questionCount;
  const QuizScreen({super.key, required this.category, this.questionCount = 10});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const int liveSeconds = 12;
  final _rng = math.Random();
  late List<_Question> _questions;
  int _index = 0;
  int _score = 0;
  bool? _correct; // null = not answered yet
  String? _answerText; // what the user signed / picked
  Lesson? _picked;
  bool _celebrating = false;
  bool _saving = false;
  bool _saveFailed = false;
  bool get _passed => _score * 100 >= _questions.length * 90; // >= 90%

  @override
  void initState() {
    super.initState();
    _questions = _buildQuestions();
  }

  List<Lesson> get _lessons => widget.category.sortedLessons
      .where((l) => l.videoAsset != null && l.videoAsset!.isNotEmpty)
      .toList();

  List<_Question> _buildQuestions() {
    final pool = _lessons;
    final n = widget.questionCount;
    final picks = <Lesson>[];
    while (picks.length < n) {
      picks.addAll([...pool]..shuffle(_rng));
    }
    final types = [for (var i = 0; i < n; i++) i < n ~/ 2]..shuffle(_rng);
    return [
      for (var i = 0; i < n; i++)
        _Question(picks[i], types[i], types[i] ? const [] : _optionsFor(picks[i], pool))
    ];
  }

  /// Correct answer + 3 distractors from the same category, preferring signs
  /// the model confuses with it (harder, and teaches the difference).
  List<Lesson> _optionsFor(Lesson target, List<Lesson> pool) {
    final byLabel = {for (final l in pool) modelLabelForLesson(l.id): l};
    final label = modelLabelForLesson(target.id);
    final opts = <Lesson>[target];
    for (final c in confusableSigns[label] ?? const <String>[]) {
      final l = byLabel[c];
      if (l != null && !opts.contains(l) && opts.length < 4) opts.add(l);
    }
    final rest = pool.where((l) => !opts.contains(l)).toList()..shuffle(_rng);
    opts.addAll(rest.take(4 - opts.length));
    return opts..shuffle(_rng);
  }

  void _answer(bool correct, String? answerText, {Lesson? picked}) {
    if (_correct != null) return;
    setState(() {
      _correct = correct;
      _answerText = answerText;
      _picked = picked;
      if (correct) _score++;
    });
    if (!correct) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showHint(_questions[_index].lesson));
    }
  }

  void _next() {
    final finishing = _index + 1 >= _questions.length;
    setState(() {
      _index++;
      _correct = null;
      _answerText = null;
      _picked = null;
    });
    if (finishing) _submitScore();
  }

  void _restart() => setState(() {
        _questions = _buildQuestions();
        _index = 0;
        _score = 0;
        _correct = null;
        _answerText = null;
        _picked = null;
        _celebrating = false;
        _saving = false;
        _saveFailed = false;
      });

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? const Color(0xFFB42318) : const Color(0xFF087F73),
        ),
      );
  }

  /// Saves the score first; the celebration only starts once it is stored, so
  /// the unlock never depends on the 5-second overlay finishing.
  Future<void> _submitScore() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showMessage('Sign in to save your score.', isError: true);
      return;
    }

    setState(() {
      _saving = true;
      _saveFailed = false;
    });

    try {
      await Supabase.instance.client.rpc('submit_quiz', params: {
        'p_category_id': widget.category.id,
        'p_score': _score,
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _celebrating = _passed;
      });
    } on AuthException catch (e) {
      _saveError('Auth error: ${e.code ?? 'unknown'}');
    } catch (_) {
      _saveError('Could not submit quiz score. Please try again.');
    }
  }

  void _saveError(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveFailed = true;
    });
    _showMessage(message, isError: true);
  }

  /// Back to the Learn screen: pops everything above CategoryDetailScreen, then
  /// CategoryDetailScreen itself, so LearnScreen's `await Navigator.push`
  /// resumes and checks for newly unlocked categories.
  void _finishQuiz() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    final result = QuizResult(
        categoryId: widget.category.id,
        score: _score,
        total: _questions.length);

    var foundDetail = false;
    nav.popUntil((r) {
      if (r.settings.name == kCategoryDetailRoute) {
        foundDetail = true;
        return true;
      }
      return r.isFirst; // safety: never pop past the root
    });
    if (foundDetail) nav.pop(result);
  }

  Future<void> _showHint(Lesson lesson) => showDialog<void>(
        context: context,
        builder: (_) => _HintDialog(lesson: lesson, months: widget.category.id == 'months'),
      );

  @override
  Widget build(BuildContext context) {
    final done = _index >= _questions.length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        title: Text('${widget.category.title} quiz',
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: done
            ? Stack(
                children: [
                  _summary(),
                  if (_celebrating)
                    Positioned.fill(
                      child: CelebrationOverlay(
                        title: 'Congratulations!',
                        message:
                            'You scored $_score / ${_questions.length} on the ${widget.category.title} quiz.',
                        onFinished: _finishQuiz,
                      ),
                    ),
                ],
              )
            : _questionView(_questions[_index]),
      ),
    );
  }

  Widget _questionView(_Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
          child: Row(
            children: [
              Text('Question ${_index + 1} / ${_questions.length}',
                  style: const TextStyle(color: _muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Score $_score',
                  style: const TextStyle(color: _teal, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_index + (_correct == null ? 0 : 1)) / _questions.length,
              color: _teal,
              backgroundColor: _border,
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: q.live
              ? _LiveQuestion(
                  key: ValueKey('live$_index'),
                  lesson: q.lesson,
                  category: widget.category,
                  seconds: liveSeconds,
                  answered: _correct != null,
                  onResult: (ok, text) => _answer(ok, text),
                )
              : _VideoQuestion(
                  key: ValueKey('video$_index'),
                  question: q,
                  answered: _correct != null,
                  picked: _picked,
                  onPick: (l) => _answer(l == q.lesson, l.title, picked: l),
                ),
        ),
        if (_correct != null) _feedback(q),
      ],
    );
  }

  Widget _feedback(_Question q) {
    final ok = _correct!;
    final color = ok ? Colors.green.shade600 : Colors.red.shade600;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? 'Correct!  +1 point' : 'Incorrect',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                Text(
                  ok
                      ? q.lesson.title
                      : 'Answer: ${q.lesson.title}'
                          '${_answerText == null ? '' : ' · yours: $_answerText'}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          if (!ok)
            TextButton(
              onPressed: () => _showHint(q.lesson),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Hint'),
            ),
          FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: color),
            child: Text(_index + 1 >= _questions.length ? 'Finish' : 'Next'),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final pct = (_score / _questions.length * 100).round();
    return Center (
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pct >= 70 ? Icons.emoji_events_rounded : Icons.school_rounded,
              size: 72, color: pct >= 70 ? const Color(0xFFE8782F) : _teal),
          const SizedBox(height: 12),
          Text('$_score / ${_questions.length}',
              style: const TextStyle(
                  color: _ink, fontSize: 40, fontWeight: FontWeight.w800)),
          Text('$pct% correct',
              style: const TextStyle(color: _muted, fontSize: 15)),
          const SizedBox(height: 16),
          if (_saving)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _teal)),
                SizedBox(width: 10),
                Text('Saving your score…',
                    style: TextStyle(color: _muted, fontSize: 13)),
              ],
            ),
            if (_saveFailed)
            OutlinedButton.icon(
              onPressed: _submitScore,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry saving score'),
              style: OutlinedButton.styleFrom(foregroundColor: _teal),
            ),
            const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _restart,
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Try again',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Back to quizzes')),
        ],
      ),
    ),
  );
}
}

/// Live Camera Challenge: sign [lesson] within [seconds]. Correct when the
/// recognizer locks on it (>= 85%); locking on another sign or running out of
/// time is incorrect.
class _LiveQuestion extends StatefulWidget {
  final Lesson lesson;
  final LearnCategory category;
  final int seconds;
  final bool answered;
  final void Function(bool correct, String? answerText) onResult;
  const _LiveQuestion({
    super.key,
    required this.lesson,
    required this.category,
    required this.seconds,
    required this.answered,
    required this.onResult,
  });

  @override
  State<_LiveQuestion> createState() => _LiveQuestionState();
}

class _LiveQuestionState extends State<_LiveQuestion> {
  late final Map<String, String> _titleByLabel = {
    for (final l in widget.category.lessons) modelLabelForLesson(l.id): l.title
  };
  late final String _target = modelLabelForLesson(widget.lesson.id);
  Timer? _timer;
  late int _left = widget.seconds;
  bool _started = false; // countdown starts once a hand is seen
  bool _done = false;
  LiveSignState? _state;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onUpdate(LiveSignState s) {
    if (_done) return;
    setState(() => _state = s);
    if (!_started && s.handCount > 0) {
      _started = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _done) return t.cancel();
        setState(() => _left--);
        if (_left <= 0) {
          t.cancel();
          _finish(false, _titleOf(_state?.prediction.sign) ?? 'no match in time');
        }
      });
    }
    if (s.locked && s.prediction.sign != null) {
      _finish(s.prediction.sign == _target, _titleOf(s.prediction.sign));
    }
  }

  String? _titleOf(String? label) => label == null ? null : (_titleByLabel[label] ?? label);

  void _finish(bool ok, String? text) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    widget.onResult(ok, text);
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            children: [
              const Icon(Icons.videocam_rounded, color: _teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Sign:  ', style: TextStyle(color: _muted, fontSize: 16)),
                  TextSpan(
                      text: widget.lesson.title,
                      style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w800)),
                ])),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _left <= 3 ? Colors.red.shade50 : const Color(0xFFE6F4F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_started ? '${_left}s' : 'Show hands',
                    style: TextStyle(
                        color: _left <= 3 ? Colors.red.shade700 : _teal, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    LiveSignView(
                      candidates: _titleByLabel.keys.toList(),
                      letters: widget.category.id == lettersCategoryId,
                      onUpdate: _onUpdate,
                    ),
                    if (s != null && s.top3.isNotEmpty)
                      Positioned(
                          top: 10, left: 10, child: Top3Panel(state: s, titleOf: (l) => _titleOf(l)!)),
                    if (!widget.answered)
                      Positioned(
                        bottom: 10,
                        left: 10,
                        right: 10,
                        child: FeedbackBanner(
                          sign: _titleOf(s?.prediction.sign),
                          confidence: s?.prediction.confidence ?? 0,
                          locked: false,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Video Identification: watch the reference clip, pick 1 of 4.
class _VideoQuestion extends StatefulWidget {
  final _Question question;
  final bool answered;
  final Lesson? picked;
  final ValueChanged<Lesson> onPick;
  const _VideoQuestion({
    super.key,
    required this.question,
    required this.answered,
    required this.picked,
    required this.onPick,
  });

  @override
  State<_VideoQuestion> createState() => _VideoQuestionState();
}

class _VideoQuestionState extends State<_VideoQuestion> {
  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      children: [
        const Row(
          children: [
            Icon(Icons.ondemand_video_rounded, color: _teal),
            SizedBox(width: 8),
            Text('Which sign is this?',
                style: TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        _LoopingVideo(asset: q.lesson.videoAsset!),
        const SizedBox(height: 16),
        for (final o in q.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionButton(
              title: o.title,
              state: !widget.answered
                  ? _OptState.idle
                  : o == q.lesson
                      ? _OptState.correct
                      : (o == widget.picked ? _OptState.wrong : _OptState.idle),
              onTap: widget.answered ? null : () => widget.onPick(o),
            ),
          ),
      ],
    );
  }
}

enum _OptState { idle, correct, wrong }

class _OptionButton extends StatelessWidget {
  final String title;
  final _OptState state;
  final VoidCallback? onTap;
  const _OptionButton({required this.title, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (state) {
      _OptState.correct => (Colors.green.shade600, Colors.white, Colors.green.shade600),
      _OptState.wrong => (Colors.red.shade600, Colors.white, Colors.red.shade600),
      _OptState.idle => (Colors.white, _ink, _border),
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (state == _OptState.correct) const Icon(Icons.check_rounded, color: Colors.white),
              if (state == _OptState.wrong) const Icon(Icons.close_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Muted, looping lesson video (the team's bundled clips).
class _LoopingVideo extends StatefulWidget {
  final String asset;
  const _LoopingVideo({required this.asset});

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
  late final VideoPlayerController _c = VideoPlayerController.asset(widget.asset);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      _c
        ..setVolume(0)
        ..setLooping(true)
        ..play();
      setState(() => _ready = true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: _ready ? _c.value.aspectRatio : 16 / 9,
          child: _ready
              ? VideoPlayer(_c)
              : const Center(child: CircularProgressIndicator(color: Color(0xFF0D9488))),
        ),
      ),
    );
  }
}

/// Red-answer pop-up: the reference video plus a short posture tip.
class _HintDialog extends StatelessWidget {
  final Lesson lesson;
  final bool months;
  const _HintDialog({required this.lesson, required this.months});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How to sign "${lesson.title}"',
                style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (lesson.videoAsset != null) _LoopingVideo(asset: lesson.videoAsset!),
            const SizedBox(height: 12),
            Text(
              months
                  ? 'Watch which hand stays still and which hand moves behind it. '
                      'Stand back so both elbows show, and turn slightly so the camera sees your signing hand.'
                  : 'Match three things: the hand shape, where the hand is (face, chest, side), '
                      'and the movement. Keep your hands inside the camera view.',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(backgroundColor: _teal),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}