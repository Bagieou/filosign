import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/auth_page.dart';

/// App-wide navigator / messenger, so the inactivity logout can leave any
/// screen and say why.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Accessibility preferences (REQ006): text size and high contrast, saved on
/// the device and applied to every screen by [AppAccessibility].
class AppSettings {
  static const textSizes = <String, double>{'Normal': 1.0, 'Large': 1.15, 'Extra large': 1.3};
  static final ValueNotifier<double> textScale = ValueNotifier(1.0);
  static final ValueNotifier<bool> highContrast = ValueNotifier(false);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      textScale.value = p.getDouble('a11y_text_scale') ?? 1.0;
      highContrast.value = p.getBool('a11y_high_contrast') ?? false;
    } catch (_) {}
  }

  static Future<void> setTextScale(double v) async {
    textScale.value = v;
    try {
      (await SharedPreferences.getInstance()).setDouble('a11y_text_scale', v);
    } catch (_) {}
  }

  static Future<void> setHighContrast(bool v) async {
    highContrast.value = v;
    try {
      (await SharedPreferences.getInstance()).setBool('a11y_high_contrast', v);
    } catch (_) {}
  }
}

/// Applies [AppSettings] to everything below it: text scale, bold text and,
/// for high contrast, a contrast boost over the whole screen (most screens use
/// fixed brand colours, so a theme alone would not reach them).
class AppAccessibility extends StatelessWidget {
  final Widget child;
  const AppAccessibility({super.key, required this.child});

  static const double _c = 1.45; // contrast factor
  static const double _o = 128 * (1 - _c);
  static const ColorFilter _contrast = ColorFilter.matrix(<double>[
    _c, 0, 0, 0, _o, //
    0, _c, 0, 0, _o, //
    0, 0, _c, 0, _o, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: AppSettings.textScale,
      builder: (context, scale, _) => ValueListenableBuilder<bool>(
        valueListenable: AppSettings.highContrast,
        builder: (context, hc, _) {
          final mq = MediaQuery.of(context);
          final content = MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(scale),
              boldText: hc || mq.boldText,
              highContrast: hc || mq.highContrast,
            ),
            child: child,
          );
          return hc ? ColorFiltered(colorFilter: _contrast, child: content) : content;
        },
      ),
    );
  }
}

/// REQ032: signs the user out after 15 minutes without a touch (or a hand in
/// front of the camera, see [InactivityGuard.activity]).
class InactivityGuard extends StatefulWidget {
  final Widget child;
  const InactivityGuard({super.key, required this.child});

  static const Duration timeout = Duration(minutes: 15);
  static DateTime _last = DateTime.now();

  /// Counts as activity (camera screens call this while hands are signing).
  static void activity() => _last = DateTime.now();

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InactivityGuard.activity();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      InactivityGuard.activity();
      return;
    }
    if (DateTime.now().difference(InactivityGuard._last) < InactivityGuard.timeout) return;
    InactivityGuard.activity();
    try {
      await auth.signOut();
    } catch (_) {}
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (_) => false,
    );
    appMessengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('You were signed out after 15 minutes of inactivity.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => InactivityGuard.activity(),
        onPointerMove: (_) => InactivityGuard.activity(),
        onPointerSignal: (_) => InactivityGuard.activity(),
        child: widget.child,
      );
}
