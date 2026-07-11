/// The production ``TransitionCoordinator``: waits for the appear/disappear
/// signals fed in by the `Routed*` views, bounded by a timeout so a missed
/// signal never wedges the executor, plus a short grace period letting the
/// presentation transaction finish before the next stage applies.
@MainActor
public final class UITransitionCoordinator: TransitionCoordinator {
    private let grace: Duration
    private let timeout: Duration

    /// - Parameters:
    ///   - grace: extra settling time after an appearance/disappearance
    ///     signal, covering the tail of the presentation animation
    ///     (`onAppear` fires near the start of it).
    ///   - timeout: upper bound on waiting for a signal that never comes.
    public init(grace: Duration = .milliseconds(150), timeout: Duration = .milliseconds(700)) {
        self.grace = grace
        self.timeout = timeout
    }

    public func settle(after stage: ExecutionStage, in scene: SceneNavigator) async throws {
        switch stage.settling {
        case .none:
            // Base mutations (tab selection, path replacement) apply in one
            // transaction; just let SwiftUI observe them.
            await Task.yield()

        case .appearance(let context):
            await withTimeout { await context.awaitAppearance() }
            try? await Task.sleep(for: grace)

        case .disappearance(let context):
            await withTimeout { await context.awaitDisappearance() }
            try? await Task.sleep(for: grace)
        }
        try Task.checkCancellation()
    }

    private func withTimeout(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
        let timeout = timeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
            }
            await group.next()
            group.cancelAll()
        }
    }
}
