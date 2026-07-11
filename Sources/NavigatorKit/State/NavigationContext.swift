import Observation

/// One presentation context: a navigation stack plus everything presented on
/// top of it.
///
/// This is the recursive node of the navigation state tree. A presented
/// sheet's content is itself a `NavigationContext`, so "a sheet containing a
/// stack that presents another sheet" is just a three-level tree.
@MainActor
@Observable
public final class NavigationContext: Identifiable {
    public let id: ContextID

    /// The route rendered at the root of this context's stack, or `nil` when
    /// the root view is supplied directly by the composition layer.
    public let root: AnyRoute?

    /// The pushed routes; binds to `NavigationStack(path:)`.
    public var path: [AnyRoute]

    /// The sheet presented over this context, if any.
    public var sheet: PresentedContext?

    /// The full-screen cover presented over this context, if any.
    public var fullScreenCover: PresentedContext?

    /// The alert shown on this context, if any.
    public var alert: RoutedAlert?

    /// The confirmation dialog shown on this context, if any.
    public var confirmationDialog: RoutedDialog?

    public init(
        root: AnyRoute? = nil,
        path: [AnyRoute] = []
    ) {
        self.id = ContextID()
        self.root = root
        self.path = path
    }

    // MARK: - Transition signaling

    /// Whether this context's view is currently installed in the view
    /// hierarchy. Maintained by the UI layer via ``signalDidAppear()`` /
    /// ``signalDidDisappear()``; used by the intent executor to await
    /// presentation transitions.
    @ObservationIgnored
    public private(set) var hasAppeared = false

    @ObservationIgnored
    private var appearanceWaiters: [CheckedContinuation<Void, Never>] = []

    @ObservationIgnored
    private var disappearanceWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the UI layer when this context's view appears.
    public func signalDidAppear() {
        hasAppeared = true
        let waiters = appearanceWaiters
        appearanceWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Called by the UI layer when this context's view disappears.
    public func signalDidDisappear() {
        hasAppeared = false
        let waiters = disappearanceWaiters
        disappearanceWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Suspends until the context's view has appeared. Returns immediately if
    /// it is already on screen.
    func awaitAppearance() async {
        guard !hasAppeared else { return }
        await withCheckedContinuation { appearanceWaiters.append($0) }
    }

    /// Suspends until the context's view has disappeared. Returns immediately
    /// if it is not on screen.
    func awaitDisappearance() async {
        guard hasAppeared else { return }
        await withCheckedContinuation { disappearanceWaiters.append($0) }
    }
}

// MARK: - Tree queries

extension NavigationContext {
    /// The presentation currently on top of this context (sheet takes
    /// precedence; SwiftUI cannot present both simultaneously).
    public var presented: PresentedContext? {
        sheet ?? fullScreenCover
    }

    /// The deepest currently-presented context — `self` if nothing is
    /// presented. Navigation conveniences like `push` target this.
    public var activeLeaf: NavigationContext {
        presented?.content.activeLeaf ?? self
    }

    /// This context followed by all presented descendant contexts, outermost
    /// first.
    public var selfAndPresentedDescendants: [NavigationContext] {
        var result: [NavigationContext] = [self]
        var current = self
        while let next = current.presented?.content {
            result.append(next)
            current = next
        }
        return result
    }

    /// The number of presentation levels above this context (0 when nothing
    /// is presented).
    public var presentationDepth: Int {
        selfAndPresentedDescendants.count - 1
    }

    /// All routes visible in this context: the root (if routed) plus the path.
    public var allRoutes: [AnyRoute] {
        (root.map { [$0] } ?? []) + path
    }

    /// Whether this context (not its descendants) shows the given route.
    public func containsRoute(_ route: AnyRoute) -> Bool {
        allRoutes.contains(route)
    }

    /// Removes the presented child (both slots) without animation semantics —
    /// state-level dismissal. The executor uses this; views bind and let
    /// SwiftUI drive the same mutation.
    public func dismissPresented() {
        sheet = nil
        fullScreenCover = nil
    }
}

/// A child context presented over a parent, together with how it is shown.
@MainActor
@Observable
public final class PresentedContext: Identifiable {
    public let id: ContextID
    public let style: PresentationStyle
    public let content: NavigationContext

    public init(style: PresentationStyle, content: NavigationContext) {
        self.id = ContextID()
        self.style = style
        self.content = content
    }
}
