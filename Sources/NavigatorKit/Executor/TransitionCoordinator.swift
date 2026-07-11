/// The seam between the executor and SwiftUI's presentation machinery.
///
/// After applying each stage, the executor asks the coordinator to wait until
/// the UI has settled enough for the next stage to be applied safely (a
/// nested sheet cannot be presented until its parent has finished appearing).
///
/// The production implementation (`UITransitionCoordinator`) awaits the
/// appear/disappear signals fed in by the `Routed*` views, with a timeout so
/// a missed signal never wedges the executor. ``ImmediateTransitionCoordinator``
/// returns instantly, making the whole executor runnable headlessly.
@MainActor
public protocol TransitionCoordinator {
    func settle(after stage: ExecutionStage, in scene: SceneNavigator) async throws
}

/// A coordinator that never waits — for headless execution and tests.
public struct ImmediateTransitionCoordinator: TransitionCoordinator {
    public init() {}
    public func settle(after stage: ExecutionStage, in scene: SceneNavigator) async throws {}
}
