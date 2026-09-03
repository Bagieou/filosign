import 'package:flutter/material.dart';

class TermsDialog extends StatefulWidget {
  final String termsText;

  const TermsDialog({super.key, required this.termsText});

  @override
  State<TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<TermsDialog> {
  final ScrollController _scroll = ScrollController();
  bool _reachedBottom = false;
  bool _agree = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_reachedBottom &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 1) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  return AlertDialog(
    // Match the horizontal padding of the AuthScreen card
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    title: const Text('Terms & Conditions'),
    content: SizedBox(
      // width is now unconstrained → it will expand to the inset width
      height: MediaQuery.of(context).size.height * 0.6,
      child: SingleChildScrollView(
        controller: _scroll,
        child: SelectableText(
          widget.termsText,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ),
    actionsAlignment: MainAxisAlignment.center,
    actions: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: _agree,
            title: const Text('I agree to the terms and conditions'),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _reachedBottom
                ? (v) => setState(() => _agree = v ?? false)
                : null,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _agree ? () => Navigator.pop(context, true) : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    ],
  );
}
}