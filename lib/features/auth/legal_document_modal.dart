import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:html/dom.dart' as dom;

class LegalDocumentModal extends StatefulWidget {
  final String title;
  final String assetPath;
  final VoidCallback onAgreed;

  const LegalDocumentModal({
    required this.title,
    required this.assetPath,
    required this.onAgreed,
    super.key,
  });

  @override
  State<LegalDocumentModal> createState() => _LegalDocumentModalState();
}

class _LegalDocumentModalState extends State<LegalDocumentModal> {
  bool _reachedBottom = false;
  bool _loaded = false;
  bool _loadFailed = false;
  String? _htmlContent;

  final ScrollController _controller = ScrollController();
  final GlobalKey _contentKey = GlobalKey();
  Timer? _settleTimer;
  int _settleRetries = 0;
  static const int _maxSettleRetries = 12; // ~3.6s of retries max

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loadHtml();
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Scroll handling
  // ---------------------------------------------------------------------------

  void _onScroll() {
    if (!_controller.hasClients || _reachedBottom) return;
    final pos = _controller.position;
    // Only unlock once we know there IS a scroll extent and the user is at the bottom.
    if (pos.maxScrollExtent > 0 &&
        pos.pixels >= pos.maxScrollExtent - 8) {
      setState(() => _reachedBottom = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Loading + settle detection
  // ---------------------------------------------------------------------------

  Future<void> _loadHtml() async {
    try {
      final data = await rootBundle.loadString(widget.assetPath);
      if (!mounted) return;
      setState(() {
        _htmlContent = data;
        _loaded = true;
      });
      _settleRetries = 0;
      _scheduleSettleCheck();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loaded = true;
      });
    }
  }

  void _scheduleSettleCheck() {
    _settleTimer?.cancel();
    _settleTimer = Timer(
      const Duration(milliseconds: 300),
      _unlockIfContentFits,
    );
  }

  /// Unlocks the button ONLY if the content has actually rendered and genuinely
  /// fits within the viewport (no scrolling needed). Otherwise stays locked
  /// until the user scrolls to the bottom.
  void _unlockIfContentFits() {
    if (!mounted || _reachedBottom) return;

    // Step 1 — confirm HtmlWidget has rendered real content.
    final ctx = _contentKey.currentContext;
    if (ctx == null) return _retrySettle();

    final rb = ctx.findRenderObject();
    if (rb is! RenderBox || !rb.hasSize || rb.size.height <= 0) {
      return _retrySettle();
    }

    // Step 2 — confirm the scroll view has attached and reported metrics.
    if (!_controller.hasClients) return _retrySettle();

    final pos = _controller.position;

    // If there IS overflow, keep locked — user must scroll to bottom.
    if (pos.maxScrollExtent > 0) return;

    // Content genuinely fits — safe to unlock.
    setState(() => _reachedBottom = true);
  }

  void _retrySettle() {
    if (_settleRetries >= _maxSettleRetries) return;
    _settleRetries++;
    _scheduleSettleCheck();
  }

  // ---------------------------------------------------------------------------
  // Styles and Builders
  // ---------------------------------------------------------------------------
  Map<String, String>? _stylesFor(dom.Element element) {
    final tag = element.localName;
    final classes = element.classes;

    if (tag == 'h1') {
      return {
        'text-align': 'center',
        'font-size': '20px',
        'font-weight': '800',
        'color': '#153B39',
        'margin': '0 0 6px 0',
        'letter-spacing': '-0.2px',
      };
    }
    if (tag == 'h2') {
      return {
        'font-size': '15px',
        'font-weight': '800',
        'color': '#087F73',
        'margin': '22px 0 8px 0',
      };
    }
    if (tag == 'span' && classes.contains('num')) {
      return {
        'font-weight': '800',
        'color': '#087F73',
      };
    }
    if (tag == 'p' && classes.contains('updated')) {
      return {
        'text-align': 'center',
        'font-style': 'italic',
        'font-size': '12px',
        'color': '#64807C',
        'margin': '0 0 4px 0',
      };
    }
    if (tag == 'p' && classes.contains('end')) {
      return {
        'text-align': 'center',
        'font-style': 'italic',
        'font-size': '12px',
        'color': '#64807C',
        'margin': '32px 0 0 0',
      };
    }
    if (tag == 'p' && classes.contains('caps')) {
      return {
        'text-align': 'justify',
        'font-size': '12.5px',
        'font-weight': '700',
        'color': '#153B39',
        'margin': '0 0 10px 0',
        'letter-spacing': '0.2px',
      };
    }
    if (tag == 'p') {
      return {
        'text-align': 'justify',
        'font-size': '13.5px',
        'color': '#153B39',
        'margin': '0 0 10px 0',
      };
    }
    if (tag == 'hr') {
      return {
        'border': 'none',
        'border-top': '1px solid #E2EEEB',
        'margin': '18px 0 24px 0',
      };
    }
    if (tag == 'ul') {
      return {
        'margin': '0 0 12px 0',
        'padding-left': '22px',
      };
    }
    if (tag == 'li') {
      return {
        'margin-bottom': '6px',
        'font-size': '13.5px',
        'color': '#153B39',
        'text-align': 'justify',
      };
    }
    if (tag == 'a') {
      return {
        'color': '#087F73',
        'text-decoration': 'underline',
      };
    }
    return null;
  }

  Widget? _widgetFor(dom.Element element) {
    final tag = element.localName;
    final classes = element.classes;

    if (tag == 'p' && classes.contains('caps')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          element.text.toUpperCase(),
          textAlign: TextAlign.justify,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            height: 1.7,
            color: Color(0xFF153B39),
            letterSpacing: 0.2,
          ),
        ),
      );
    }
    if (tag == 'p' && classes.contains('end')) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE2EEEB))),
          ),
          child: Text(
            element.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Color(0xFF64807C),
            ),
          ),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool canAgree = _reachedBottom && _loaded && !_loadFailed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18087F73),
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------- Header (fixed) ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 12, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 22,
                  color: Color(0xFF087F73),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF153B39),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF64807C),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE3EFEC)),

          // ---------- Body (scrollable) ----------
          Flexible(
            child: !_loaded
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _loadFailed
                    ? const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 40,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFB42318),
                              size: 40,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Could not load this document.\nPlease try again later.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Color(0xFF64807C)),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _controller,
                        padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
                        child: Container(
                          // This key lets us verify the HTML actually
                          // rendered (height > 0) before trusting the
                          // scroll metrics.
                          key: _contentKey,
                          child: HtmlWidget(
                            _htmlContent ?? '',
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              height: 1.7,
                              color: Color(0xFF153B39),
                            ),
                            customStylesBuilder: _stylesFor,
                            customWidgetBuilder: _widgetFor,
                            onTapUrl: (url) async {
                              debugPrint('Tapped link: $url');
                              return true;
                            },
                          ),
                        ),
                      ),
          ),
          const Divider(height: 1, color: Color(0xFFE3EFEC)),

          // ---------- Footer (sticky) ----------
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!canAgree && !_loadFailed && _loaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Scroll to the bottom to continue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64807C),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    // null = disabled (gray); enabled only when canAgree.
                    onPressed: canAgree
                        ? () {
                            widget.onAgreed();
                            Navigator.of(context).pop();
                          }
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF087F73),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE3E6E5),
                      disabledForegroundColor: const Color(0xFF9AA5A3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'I agree',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}