import Foundation

/// Decides which scene (window) should handle an incoming intent — or that a
/// new window should be opened for it. Apps customize cross-window routing by
/// conforming to this.
@MainActor
public protocol SceneSelectionPolicy {
    func decide(
        intent: NavigationIntent,
        url: URL?,
        scenes: [SceneNavigator],
        activeSceneID: SceneID?
    ) -> SceneDecision
}

/// The outcome of scene selection.
public enum SceneDecision: Sendable {
    /// Execute in the most recently active scene (or the first registered
    /// one).
    case useActive
    /// Execute in a specific registered scene.
    case use(SceneID)
    /// Open a new window (of the given `WindowGroup` id, or the default
    /// group) and execute there once it registers. Falls back to the active
    /// scene on platforms without multi-window support.
    case openNewWindow(windowID: String? = nil)
}

/// Caller-side override of the policy for one ``AppNavigator/perform(_:scenePreference:)``.
public enum ScenePreference: Sendable {
    /// Let the ``SceneSelectionPolicy`` decide.
    case automatic
    /// Force the active scene.
    case activeScene
    /// Force a specific scene.
    case scene(SceneID)
    /// Force a new window.
    case newWindow(windowID: String? = nil)
}

// MARK: - Built-in policies

/// Always uses the active scene — the right default on iPhone.
public struct ReuseActiveScenePolicy: SceneSelectionPolicy {
    public init() {}

    public func decide(
        intent: NavigationIntent,
        url: URL?,
        scenes: [SceneNavigator],
        activeSceneID: SceneID?
    ) -> SceneDecision {
        .useActive
    }
}

/// Reuses a scene that already shows the intent's primary route (exact match
/// first, then same route type) — possible because navigation trees are
/// inspectable. Otherwise applies the configured fallback.
public struct ReuseSceneShowingRoutePolicy: SceneSelectionPolicy {
    public enum Fallback: Sendable {
        case useActive
        case openNewWindow(windowID: String? = nil)
    }

    private let fallback: Fallback

    public init(fallback: Fallback = .useActive) {
        self.fallback = fallback
    }

    public func decide(
        intent: NavigationIntent,
        url: URL?,
        scenes: [SceneNavigator],
        activeSceneID: SceneID?
    ) -> SceneDecision {
        guard let route = intent.primaryRoute else { return .useActive }
        if let exact = scenes.first(where: { $0.contains(route) }) {
            return .use(exact.id)
        }
        if let sameType = scenes.first(where: { scene in
            scene.findRoute(where: { $0.typeID == route.typeID }) != nil
        }) {
            return .use(sameType.id)
        }
        switch fallback {
        case .useActive: return .useActive
        case .openNewWindow(let windowID): return .openNewWindow(windowID: windowID)
        }
    }
}

/// Always opens a new window — a macOS document-style pattern.
public struct AlwaysNewWindowPolicy: SceneSelectionPolicy {
    private let windowID: String?

    public init(windowID: String? = nil) {
        self.windowID = windowID
    }

    public func decide(
        intent: NavigationIntent,
        url: URL?,
        scenes: [SceneNavigator],
        activeSceneID: SceneID?
    ) -> SceneDecision {
        .openNewWindow(windowID: windowID)
    }
}

extension NavigationIntent {
    /// The route the intent ultimately lands on — used by scene policies to
    /// match intents against what scenes already show.
    public var primaryRoute: AnyRoute? {
        for operation in operations.reversed() {
            switch operation {
            case .push(let route), .popTo(let route):
                return route
            case .present(let route, _):
                return route
            case .activate(let route, _):
                return route
            case .setPath(let path):
                if let last = path.last { return last }
            case .selectSidebar(let selection):
                if let selection { return selection }
            default:
                continue
            }
        }
        return nil
    }
}
