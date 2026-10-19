/// Team test version: every category open (Learn, Practice, Search), a
/// separate Quiz card on Home, and the Top-3 panel on camera screens.
/// The normal app is unchanged; build the test version with
/// `--dart-define=FILOSIGN_TEST_BUILD=true`.
const bool kTestBuild = bool.fromEnvironment('FILOSIGN_TEST_BUILD');
