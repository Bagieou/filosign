import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One step of the first-run tour: the widget to highlight and what to say.
class CoachStep {
  final GlobalKey target;
  final String title;
  final String body;
  const CoachStep(this.target, this.title, this.body);
}

/// REQ042: onboarding tooltips. Dims the screen, cuts a highlight around each
/// target in turn and explains it, with Next / Skip. Shown once per device;
/// [CoachMarks.reset] brings it back (Settings > Show app tour again).
class CoachMarks {
  static const _prefKey = 'onboarding_tour_done';

  static Future<void> reset() async {
    try {
      (await SharedPreferences.getInstance()).setBool(_prefKey, false);
    } catch (_) {}
  }

  static Future<void> showOnce(BuildContext context, List<CoachStep> steps) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefKey) ?? false) return;
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    // A dialog route (not a bare overlay): the phone's Back button closes the
    // tour like Skip instead of leaving the dimmed layer stuck on screen.
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) => _CoachOverlay(
        steps: steps,
        onDone: () => Navigator.of(dialogContext).pop(),
      ),
    );
    try {
      await prefs.setBool(_prefKey, true);
    } catch (_) {}
  }
}

class _CoachOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final VoidCallback onDone;
  const _CoachOverlay({required this.steps, required this.onDone});

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> {
  int _i = 0;

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _next() {
    // skip steps whose target isn't on screen
    var n = _i + 1;
    while (n < widget.steps.length && _rectOf(widget.steps[n].target) == null) {
      n++;
    }
    if (n >= widget.steps.length) {
      widget.onDone();
    } else {
      setState(() => _i = n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final screen = MediaQuery.of(context).size;
    final r = _rectOf(step.target)?.inflate(6) ??
        Rect.fromCenter(center: screen.center(Offset.zero), width: 0, height: 0);
    final below = r.center.dy < screen.height * 0.55;
    final last = _i == widget.steps.length - 1;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              child: CustomPaint(painter: _ScrimPainter(r)),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: below ? r.bottom + 14 : null,
            bottom: below ? null : screen.height - r.top + 14,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: const TextStyle(
                          color: Color(0xFF153B39), fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(step.body, style: const TextStyle(color: Color(0xFF3F5B57), height: 1.35)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('${_i + 1} of ${widget.steps.length}',
                          style: const TextStyle(color: Color(0xFF6B8581), fontSize: 12)),
                      const Spacer(),
                      if (!last)
                        TextButton(onPressed: widget.onDone, child: const Text('Skip')),
                      FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F73)),
                        child: Text(last ? 'Got it' : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect hole;
  _ScrimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(14)));
    canvas.drawPath(path, Paint()..color = const Color(0xB3000000));
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(14)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF5EEAD4),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.hole != hole;
}
