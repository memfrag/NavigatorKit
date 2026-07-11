import Observation

/// Per-scene navigation state: one of these exists per window, owning the
/// scene's complete navigation tree.
///
/// `SceneNavigator` is pure state plus tree queries. Mutation with correct
/// sequencing is the ``IntentExecutor``'s job; views bind to the tree via the
/// `Routed*` views and mutate it through SwiftUI bindings (swipe-back,
/// interactive dismiss), which is safe because the tree is the single source
/// of truth.
@MainActor
@Observable
public final class SceneNavigator: Identifiable {
    public let id: SceneID

    /// The scene's root container shape.
    public let root: RootLayout

    /// A presentation covering the entire root (e.g. onboarding over the tab
    /// bar). Takes precedence over per-context presentations.
    public var rootPresentation: PresentedContext?

    public init(root: RootLayout) {
        self.id = SceneID()
        self.root = root
    }
}

// MARK: - Tree queries

extension SceneNavigator {
    /// The context new navigation operations target by default: the deepest
    /// presented leaf of the root presentation if one is up, otherwise the
    /// deepest leaf of the current base context.
    public var activeContext: NavigationContext {
        if let rootPresentation {
            return rootPresentation.content.activeLeaf
        }
        return root.primaryContext.activeLeaf
    }

    /// The current base context (selected tab / detail column), ignoring
    /// presentations.
    public var baseContext: NavigationContext {
        root.primaryContext
    }

    /// Every context in the scene, including presented descendants.
    public var allContexts: [NavigationContext] {
        var contexts = root.allContexts
        if let rootPresentation {
            contexts += rootPresentation.content.selfAndPresentedDescendants
        }
        return contexts
    }

    /// Whether any context in the scene currently shows the given route.
    public func contains(_ route: AnyRoute) -> Bool {
        findRoute { $0 == route } != nil
    }

    /// Whether any context in the scene shows a route of the given type.
    public func containsRoute<R: Route>(ofType type: R.Type) -> Bool {
        findRoute { $0.is(type) } != nil
    }

    /// Finds the first route matching the predicate, searching the root
    /// layout (contexts, presented descendants, and split sidebars) in layout
    /// order, then any root presentation chain.
    public func findRoute(where predicate: (AnyRoute) -> Bool) -> RouteLocation? {
        if let found = root.findRoute(where: predicate) {
            return found
        }
        if let rootPresentation {
            for context in rootPresentation.content.selfAndPresentedDescendants {
                if let found = context.findRoute(where: predicate) {
                    return found
                }
            }
        }
        return nil
    }
}

/// Where in a scene's tree a route was found.
public enum RouteLocation {
    /// The route is a context's root view or an element of its stack path.
    case inContext(NavigationContext, ContextPosition)
    /// The route is a split view's sidebar root or sidebar selection.
    case inSidebar(SplitLayout, SidebarSlot)

    public enum ContextPosition: Hashable, Sendable {
        /// The context's root view.
        case root
        /// An element of the context's stack path.
        case path(index: Int)
    }

    public enum SidebarSlot: Hashable, Sendable {
        case root
        case selection
    }

    /// The context showing the route, when found in one.
    public var context: NavigationContext? {
        if case .inContext(let context, _) = self { return context }
        return nil
    }

    /// The route's position within its context, when found in one.
    public var position: ContextPosition? {
        if case .inContext(_, let position) = self { return position }
        return nil
    }
}

extension NavigationContext {
    /// Finds a matching route in this single context (root or path), not
    /// descending into presentations.
    func findRoute(where predicate: (AnyRoute) -> Bool) -> RouteLocation? {
        if let root, predicate(root) {
            return .inContext(self, .root)
        }
        if let index = path.firstIndex(where: predicate) {
            return .inContext(self, .path(index: index))
        }
        return nil
    }
}

extension RootLayout {
    /// Finds a matching route anywhere in this layout, including presented
    /// descendants and split sidebar roots/selections.
    @MainActor
    func findRoute(where predicate: (AnyRoute) -> Bool) -> RouteLocation? {
        switch self {
        case .stack(let context):
            for descendant in context.selfAndPresentedDescendants {
                if let found = descendant.findRoute(where: predicate) {
                    return found
                }
            }
            return nil

        case .tabs(let tabs):
            for tab in tabs.tabs {
                if let found = tab.content.findRoute(where: predicate) {
                    return found
                }
            }
            return nil

        case .split(let split):
            if let sidebarRoot = split.sidebarRoot, predicate(sidebarRoot) {
                return .inSidebar(split, .root)
            }
            if let selection = split.sidebarSelection, predicate(selection) {
                return .inSidebar(split, .selection)
            }
            let columns = (split.contentContext.map { [$0] } ?? []) + [split.detailContext]
            for column in columns {
                for descendant in column.selfAndPresentedDescendants {
                    if let found = descendant.findRoute(where: predicate) {
                        return found
                    }
                }
            }
            return nil
        }
    }
}
