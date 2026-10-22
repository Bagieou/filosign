/// Team test version: every category open (Learn, Practice, Search), a
/// separate Quiz card on Home, and the Top-3 panel on camera screens.
/// The normal app is unchanged; build the test version with
/// `--dart-define=FILOSIGN_TEST_BUILD=true`.
const bool kTestBuild = bool.fromEnvironment('FILOSIGN_TEST_BUILD');

/// User-testing release: every category open (and the Quiz card on Home), so
/// a timed session can reach any sign - but WITHOUT the TEST tools (no Top-3
/// panel, no attempt recording). Build with
/// `--dart-define=FILOSIGN_ALL_OPEN=true`. The TEST build implies it.
const bool kAllOpen = kTestBuild || bool.fromEnvironment('FILOSIGN_ALL_OPEN');
