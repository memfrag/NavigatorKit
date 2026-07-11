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

    @State private var model = SceneRootModel()
    @Environment(\.scenePhase) private var scenePhase

    /// A standalone scene root — no cross-window coordination.
    public init(blueprint: SceneBlueprint, registry: DestinationRegistry) {
        self.blueprint = blueprint
        self.registry = registry
        self.app = nil
    }

    /// A scene root coordinated by the app-level navigator.
    public init(app: AppNavigator, blueprint: SceneBlueprint) {
        self.blueprint = blueprint
        self.registry = app.destinations
        self.app = app
    }

    public var body: some View {
        let navigator = model.navigator(blueprint: blueprint, registry: registry)
        RoutedRootView(layout: navigator.scene.root)
            .modifier(RootPresentationModifier(scene: navigator.scene))
            .background {
                if let app {
                    WindowOpenerView(app: app, navigator: navigator)
                }
            }
            .environment(navigator)
            .environment(\.destinationRegistry, registry)
            .task {
                guard let app else { return }
                if let claimed = app.register(navigator) {
                    navigator.perform(claimed)
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
/// rebuild the state tree.
@MainActor
@Observable
final class SceneRootModel {
    private var storedNavigator: Navigator?

    func navigator(blueprint: SceneBlueprint, registry: DestinationRegistry) -> Navigator {
        if let storedNavigator {
            return storedNavigator
        }
        let navigator = Navigator(scene: blueprint.makeSceneNavigator(), registry: registry)
        storedNavigator = navigator
        return navigator
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
