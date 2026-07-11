/// Executes ``NavigationIntent``s against a scene's state tree with correct
/// sequencing: plan → apply stage → wait for the UI to settle → next stage.
///
/// Intents are serialized per executor: a new intent cancels the in-flight
/// one (at its next stage boundary) and waits for it to unwind before
/// planning against the settled state.
@MainActor
public final class IntentExecutor {
    private let transitions: any TransitionCoordinator
    private var current: Task<Void, any Error>?

    public init(transitions: any TransitionCoordinator) {
        self.transitions = transitions
    }

    /// Plans and executes the intent. Throws ``NavigationError`` for
    /// unplannable intents and `CancellationError` when superseded by a newer
    /// intent.
    public func execute(_ intent: NavigationIntent, on scene: SceneNavigator) async throws {
        current?.cancel()
        let previous = current
        let task = Task { @MainActor [transitions] in
            // Let the superseded intent unwind before planning against the tree.
            _ = await previous?.result
            try Task.checkCancellation()

            let plan = try Planner.plan(intent, in: scene)
            for stage in plan.stages {
                try Task.checkCancellation()
                stage.apply()
                try await transitions.settle(after: stage, in: scene)
            }
        }
        current = task
        try await task.value
    }
}
