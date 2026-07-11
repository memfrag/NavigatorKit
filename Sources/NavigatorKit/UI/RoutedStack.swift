import SwiftUI

/// A `NavigationStack` bound to a ``NavigationContext``: path, destinations,
/// and all route-driven presentations (sheets, covers, alerts, dialogs) —
/// recursively, since presented content is itself a `RoutedStack`.
public struct RoutedStack<RootContent: View>: View {
    @Bindable private var context: NavigationContext
    private let rootContent: RootContent

    @Environment(\.destinationRegistry) private var registry

    /// A stack whose root view is supplied by the caller (composition layer).
    public init(context: NavigationContext, @ViewBuilder root: () -> RootContent) {
        self.context = context
        self.rootContent = root()
    }

    public var body: some View {
        NavigationStack(path: $context.path) {
            rootContent
                .navigationDestination(for: AnyRoute.self) { route in
                    registry.view(for: route)
                }
        }
        .routedPresentations(context)
        .environment(\.navigationContext, context)
    }
}

extension RoutedStack where RootContent == RegistryRootView {
    /// A stack whose root view is resolved from the context's ``NavigationContext/root``
    /// route via the destination registry.
    public init(context: NavigationContext) {
        self.init(context: context) {
            RegistryRootView(context: context)
        }
    }
}

/// Resolves a context's root route through the destination registry.
public struct RegistryRootView: View {
    let context: NavigationContext

    @Environment(\.destinationRegistry) private var registry

    public var body: some View {
        if let root = context.root {
            registry.view(for: root)
        } else {
            UnregisteredRouteView(typeID: "<no root route>")
        }
    }
}
