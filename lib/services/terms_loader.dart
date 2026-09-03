import 'package:flutter/services.dart';

class TermsLoader {
  static Future<String> load() async {
    return await rootBundle.loadString('assets/terms/terms.md');
  }
}