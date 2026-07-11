import SwiftUI

/// The entry view for one scene (window): instantiates the scene's
/// navigation state from a ``SceneBlueprint``, installs the ``Navigator``
/// and destination registry in the environment, and renders the root layout
/// plus the scene-level presentation slot.
public struct RoutedSceneRoot: View {
    private let blueprint: SceneBlueprint
    private let registry: DestinationRegistry

    @State private var model = SceneRootModel()

    public init(blueprint: SceneBlueprint, registry: DestinationRegistry) {
        self.blueprint = blueprint
        self.registry = registry
    }

    public var body: some View {
        let navigator = model.navigator(blueprint: blueprint, registry: registry)
        RoutedRootView(layout: navigator.scene.root)
            .modifier(RootPresentationModifier(scene: navigator.scene))
            .environment(navigator)
            .environment(\.destinationRegistry, registry)
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
