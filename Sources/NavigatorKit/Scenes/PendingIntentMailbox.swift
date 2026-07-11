/// Holds intents that have no scene to run in yet:
/// - cold launch from a deep link (the URL arrives before any scene exists),
/// - intents destined for a window that is still opening.
///
/// The next scene to register with ``AppNavigator`` claims the oldest
/// pending intent.
@MainActor
final class PendingIntentMailbox {
    private var pending: [NavigationIntent] = []

    func deposit(_ intent: NavigationIntent) {
        pending.append(intent)
    }

    func claim() -> NavigationIntent? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    var isEmpty: Bool { pending.isEmpty }
}
