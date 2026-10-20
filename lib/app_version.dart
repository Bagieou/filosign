import 'test_build.dart';

/// Shown on the sign-in screen and in Settings, so testers can tell which
/// build is installed (APKs on the shared drive are named the same way).
const String kAppVersionLabel =
    'FiloSign v18 · 2026-10-21${kTestBuild ? ' · TEST (all signs open)' : ''}';
