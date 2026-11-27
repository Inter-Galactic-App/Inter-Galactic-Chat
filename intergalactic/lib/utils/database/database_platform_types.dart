/// Outcome of an attempt to re-establish a released connection.
///
/// [deferred] is a NORMAL state, not an error. Under the App Group migration the
/// database file carries `completeUntilFirstUserAuthentication`, so before the
/// device's first unlock it is genuinely unreadable and re-establish MUST fail.
/// The outcome to design against is a silent failure surfacing as arbitrary
/// query errors deep in the Matrix SDK, far from the cause.
/// [closed] is also not an error, and it is not [failed]: the wrapper was
/// closed while it was released, so it is out of the registry, holds no
/// executor and can never be re-established. A sweep that keeps treating it as
/// pending never finishes resuming, and sync stays stopped for the accounts
/// that are still live. The distinction exists so the trigger can discard it.
///
/// This lives apart from `ReleasableConnection` so both sides of the
/// `database_platform.dart` conditional export can name it without either one
/// importing the other. `releasable_connection.dart` re-exports it, so no
/// consumer's import changes.
enum ReestablishResult { established, deferred, failed, closed }
