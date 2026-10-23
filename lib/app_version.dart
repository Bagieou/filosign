import 'test_build.dart';

/// Shown on the sign-in screen and in Settings, so testers can tell which
/// build is installed (APKs on the shared drive are named the same way).
const String kAppVersionLabel =
    'FiloSign v31 · 2026-10-23${kTestBuild ? ' · TEST (all signs open)' : (kAllOpen ? ' · all categories open' : '')}';
