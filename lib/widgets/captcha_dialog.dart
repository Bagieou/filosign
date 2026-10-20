import 'dart:math' as math;

import 'package:flutter/material.dart';

/// REQ034: a text CAPTCHA shown before an account is created. Five characters
/// drawn rotated and shifted over noise lines; the user types them back.
/// (Check happens in the app; a server-side CAPTCHA can be switched on later
/// in Supabase Auth settings.)
Future<bool> showCaptchaDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CaptchaDialog(),
  );
  return ok ?? false;
}

class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog();

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  // no look-alikes (0/O, 1/I/l)
  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final _rng = math.Random();
  final _input = TextEditingController();
  late String _code;
  int _seed = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newCode();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _newCode() {
    _code = String.fromCharCodes(
        List.generate(5, (_) => _chars.codeUnitAt(_rng.nextInt(_chars.length))));
    _seed = _rng.nextInt(1 << 30);
    _input.clear();
  }

  void _verify() {
    if (_input.text.trim().toUpperCase() == _code) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = 'That did not match. Try this new one.';
        _newCode();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick check'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Type the characters you see, to show you are not a robot.'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'CAPTCHA image',
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F7F6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2EEEB)),
                    ),
                    child: CustomPaint(painter: _CaptchaPainter(_code, _seed)),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'New characters',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => setState(() {
                  _error = null;
                  _newCode();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Characters',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _verify, child: const Text('Verify')),
      ],
    );
  }
}

class _CaptchaPainter extends CustomPainter {
  final String code;
  final int seed;
  _CaptchaPainter(this.code, this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final noise = Paint()..strokeWidth = 1.4;
    for (var i = 0; i < 7; i++) {
      noise.color = Color.fromARGB(110, rng.nextInt(160), 90 + rng.nextInt(100), 110 + rng.nextInt(100));
      canvas.drawLine(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), noise);
    }
    final step = size.width / (code.length + 1);
    for (var i = 0; i < code.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: code[i],
          style: TextStyle(
            fontSize: 26 + rng.nextDouble() * 8,
            fontWeight: FontWeight.w800,
            color: Color.fromARGB(255, 10 + rng.nextInt(60), 70 + rng.nextInt(60), 70 + rng.nextInt(60)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(step * (i + 1), size.height / 2 + (rng.nextDouble() - 0.5) * 12);
      canvas.rotate((rng.nextDouble() - 0.5) * 0.7);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    final dots = Paint()..color = const Color(0x55087F73);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), 1.2, dots);
    }
  }

  @override
  bool shouldRepaint(covariant _CaptchaPainter old) => old.code != code || old.seed != seed;
}
