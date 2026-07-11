import SwiftUI

/// The entry view for one scene (window): instantiates the scene's
/// navigation state from a ``SceneBlueprint``, installs the ``Navigator``
/// and destination registry in the environment, and renders the root layout
/// plus the scene-level presentation slot.
///
/// When created with an ``AppNavigator``, the scene registers itself for
/// cross-window coordination: it claims parked deep-link intents (cold
/// launch, open-in-new-window), reports activation, and hosts the window
/// opener bridge.
public struct RoutedSceneRoot: View {
    private let blueprint: SceneBlueprint
    private let registry: DestinationRegistry
    private let app: AppNavigator?
    private let restorationEnabled: Bool

    @State private var model = SceneRootModel()
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage private var persistedState: Data?

    /// A standalone scene root — no cross-window coordination.
    /// - Parameter restorationKey: when non-nil, the scene's navigation
    ///   state is persisted to `SceneStorage` (inherently per-window) under
    ///   this key and restored on launch.
    public init(
        blueprint: SceneBlueprint,
        registry: DestinationRegistry,
        restorationKey: String? = nil
    ) {
        self.blueprint = blueprint
        self.registry = registry
        self.app = nil
        self.restorationEnabled = restorationKey != nil
        self._persistedState = SceneStorage(restorationKey ?? "navigatorkit.state")
    }

    /// A scene root coordinated by the app-level navigator.
    public init(app: AppNavigator, blueprint: SceneBlueprint, restorationKey: String? = nil) {
        self.blueprint = blueprint
        self.registry = app.destinations
        self.app = app
        self.restorationEnabled = restorationKey != nil
        self._persistedState = SceneStorage(restorationKey ?? "navigatorkit.state")
    }

    public var body: some View {
        let navigator = model.navigator(
            blueprint: blueprint,
            registry: registry,
            restoringFrom: restorationEnabled ? persistedState : nil
        )
        RoutedRootView(layout: navigator.scene.root)
            .modifier(RootPresentationModifier(scene: navigator.scene))
            .background {
                if let app {
                    WindowOpenerView(app: app, navigator: navigator)
                }
            }
            .environment(navigator)
            .environment(app)
            .environment(\.destinationRegistry, registry)
            .task {
                if let app, let claimed = app.register(navigator) {
                    try? await navigator.perform(claimed)
                }
                if restorationEnabled {
                    await model.runPersistenceLoop(scene: navigator.scene) { persistedState = $0 }
                }
            }
            .onDisappear {
                app?.unregister(sceneID: navigator.scene.id)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    app?.sceneDidBecomeActive(navigator.scene.id)
                }
            }
    }
}

/// Owns the lazily created per-scene navigator so that view updates never
/// rebuild the state tree, plus the persistence loop.
@MainActor
@Observable
final class SceneRootModel {
    private var storedNavigator: Navigator?

    func navigator(
        blueprint: SceneBlueprint,
        registry: DestinationRegistry,
        restoringFrom persisted: Data? = nil
    ) -> Navigator {
        if let storedNavigator {
            return storedNavigator
        }
        let scene = blueprint.makeSceneNavigator()
        if let persisted,
            let (snapshot, report) = NavigationSnapshotCoder.decode(persisted, routeTypes: registry.routeTypes)
        {
            scene.restore(snapshot)
            #if DEBUG
                if !report.isClean {
                    print("NavigatorKit restoration dropped routes: \(report.droppedRouteTypeIDs)")
                }
            #endif
        }
        let navigator = Navigator(scene: scene, registry: registry)
        storedNavigator = navigator
        return navigator
    }

    /// Re-encodes the scene's snapshot (debounced) whenever observable
    /// navigation state changes.
    func runPersistenceLoop(
        scene: SceneNavigator,
        write: @escaping @MainActor (Data?) -> Void
    ) async {
        while !Task.isCancelled {
            await Self.nextChange(of: scene)
            // Debounce bursts (staged intents mutate several times).
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            write(try? NavigationSnapshotCoder.encode(scene.snapshot()))
        }
    }

    private static func nextChange(of scene: SceneNavigator) async {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                // Touch every persisted property by capturing a snapshot.
                _ = scene.snapshot()
            } onChange: {
                continuation.resume()
            }
        }
    }
}

/// Binds ``SceneNavigator/rootPresentation`` (a presentation covering the
/// whole root, e.g. onboarding over the tab bar).
struct RootPresentationModifier: ViewModifier {
    @Bindable var scene: SceneNavigator

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .sheet(item: sheetBinding) { PresentedContentView(presented: $0) }
                .fullScreenCover(item: coverBinding) { PresentedContentView(presented: $0) }
        #else
            content
                .sheet(item: sheetBinding) { PresentedContentView(presented: $0) }
                .background(
                    Color.clear.sheet(item: coverBinding) { PresentedContentView(presented: $0) }
                )
        #endif
    }

    private var sheetBinding: Binding<PresentedContext?> {
        Binding(
            get: { scene.rootPresentation?.style.isFullScreenCover == false ? scene.rootPresentation : nil },
            set: { if $0 == nil { scene.rootPresentation = nil } }
        )
    }

    private var coverBinding: Binding<PresentedContext?> {
        Binding(
            get: { scene.rootPresentation?.style.isFullScreenCover == true ? scene.rootPresentation : nil },
            set: { if $0 == nil { scene.rootPresentation = nil } }
        )
    }
}
