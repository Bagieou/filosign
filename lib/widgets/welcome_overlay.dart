import 'package:flutter/material.dart';

/// A transparent overlay that shows the home icon + welcome message and fades out after 3 seconds.
class _WelcomeOverlayWidget extends StatefulWidget {
  final String message;
  final VoidCallback onComplete;

  const _WelcomeOverlayWidget({
    required this.message,
    required this.onComplete,
  });

  @override
  State<_WelcomeOverlayWidget> createState() => _WelcomeOverlayWidgetState();
}

class _WelcomeOverlayWidgetState extends State<_WelcomeOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..forward();

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(CurveTween(curve: Curves.easeOut)),
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon (same as HomeBody)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFBF1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.sign_language,
                    size: 64,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 16),
                // Welcome message
                Text(
                  widget.message,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0F766E),
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start learning Filipino Sign Language through simple lessons and practice.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper to show the welcome overlay from anywhere that has a BuildContext.
class WelcomeOverlay {
  static OverlayEntry? _currentEntry;

  static void show(BuildContext context, String message) {
    // Remove any existing overlay first
    hide();

    _currentEntry = OverlayEntry(
      builder: (ctx) => _WelcomeOverlayWidget(
        message: message,
        onComplete: hide,
      ),
    );
    Overlay.of(context).insert(_currentEntry!);
  }

  static void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
  }
}