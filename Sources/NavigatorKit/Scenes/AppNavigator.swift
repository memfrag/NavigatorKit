import Foundation
import Observation

/// The app-level coordinator: receives deep links, resolves them to intents,
/// picks the scene to run them in (or requests a new window), and tracks the
/// live scenes.
///
/// One `AppNavigator` exists per app; one ``Navigator``/``SceneNavigator``
/// pair exists per window and registers here via `RoutedSceneRoot`.
///
/// ```swift
/// @main struct ShopApp: App {
///     @State private var appNavigator = AppNavigator(
///         destinations: DestinationRegistry { ProductsFeature.destinations },
///         deepLinks: ShopDeepLinks.map,
///         scenePolicy: ReuseSceneShowingRoutePolicy(fallback: .openNewWindow())
///     )
///
///     var body: some Scene {
///         WindowGroup(id: "main") {
///             RoutedSceneRoot(app: appNavigator, blueprint: ShopBlueprint.main)
///                 .onOpenURL { appNavigator.open($0) }
///         }
///     }
/// }
/// ```
@MainActor
@Observable
public final class AppNavigator {
    public let destinations: DestinationRegistry
    public let deepLinks: DeepLinkMap

    @ObservationIgnored
    public var scenePolicy: any SceneSelectionPolicy

    /// Called when ``open(_:)`` receives a URL no pattern matches.
    @ObservationIgnored
    public var onUnhandledURL: @MainActor (URL) -> Void = { _ in }

    /// Live per-scene navigators, in registration order.
    public private(set) var navigators: [Navigator] = []

    /// The most recently active scene.
    public private(set) var activeSceneID: SceneID?

    /// Window-open requests awaiting a `WindowOpenerView` (the `openWindow`
    /// action only exists inside views).
    public private(set) var pendingWindowRequests: [WindowOpenRequest] = []

    let mailbox = PendingIntentMailbox()

    /// The `WindowGroup` id used for window-open requests that don't name
    /// one.
    public let defaultWindowID: String

    public init(
        destinations: DestinationRegistry,
        deepLinks: DeepLinkMap = DeepLinkMap(patterns: []),
        scenePolicy: any SceneSelectionPolicy = ReuseActiveScenePolicy(),
        defaultWindowID: String = "main"
    ) {
        self.destinations = destinations
        self.deepLinks = deepLinks
        self.scenePolicy = scenePolicy
        self.defaultWindowID = defaultWindowID
    }

    // MARK: - Entry points

    /// Handles a deep link (`onOpenURL`, universal link, notification tap):
    /// pattern match → intent → scene selection → execution.
    public func open(_ url: URL) {
        guard let intent = deepLinks.intent(for: url) else {
            onUnhandledURL(url)
            return
        }
        dispatch(intent, url: url, preference: .automatic)
    }

    /// Executes an intent in whichever scene the policy (or preference)
    /// selects.
    public func perform(_ intent: NavigationIntent, scenePreference: ScenePreference = .automatic) {
        dispatch(intent, url: nil, preference: scenePreference)
    }

    private func dispatch(_ intent: NavigationIntent, url: URL?, preference: ScenePreference) {
        // Cold launch: no scene yet. Park the intent; the first scene to
        // register claims it.
        guard !navigators.isEmpty else {
            mailbox.deposit(intent)
            return
        }

        let decision: SceneDecision =
            switch preference {
            case .automatic:
                scenePolicy.decide(
                    intent: intent,
                    url: url,
                    scenes: navigators.map(\.scene),
                    activeSceneID: activeSceneID
                )
            case .activeScene:
                .useActive
            case .scene(let id):
                .use(id)
            case .newWindow(let windowID):
                .openNewWindow(windowID: windowID)
            }

        switch decision {
        case .useActive:
            (activeNavigator ?? navigators[0]).perform(intent)
        case .use(let id):
            (navigator(for: id) ?? activeNavigator ?? navigators[0]).perform(intent)
        case .openNewWindow(let windowID):
            mailbox.deposit(intent)
            pendingWindowRequests.append(WindowOpenRequest(windowID: windowID))
        }
    }

    // MARK: - Scene lifecycle (called by RoutedSceneRoot)

    /// Registers a scene's navigator. Returns a parked intent for the new
    /// scene to execute, if one is waiting.
    public func register(_ navigator: Navigator) -> NavigationIntent? {
        if !navigators.contains(where: { $0.scene.id == navigator.scene.id }) {
            navigators.append(navigator)
        }
        if activeSceneID == nil {
            activeSceneID = navigator.scene.id
        }
        return mailbox.claim()
    }

    public func unregister(sceneID: SceneID) {
        navigators.removeAll { $0.scene.id == sceneID }
        if activeSceneID == sceneID {
            activeSceneID = navigators.last?.scene.id
        }
    }

    public func sceneDidBecomeActive(_ sceneID: SceneID) {
        activeSceneID = sceneID
    }

    /// Marks a window request as handled; when multi-window is unsupported,
    /// the caller runs the parked intent in the current scene instead.
    func consumeWindowRequest(_ request: WindowOpenRequest, openedWindow: Bool, fallback: Navigator?) {
        pendingWindowRequests.removeAll { $0.id == request.id }
        if !openedWindow, let fallback, let intent = mailbox.claim() {
            fallback.perform(intent)
        }
    }

    // MARK: - Lookup

    public var activeNavigator: Navigator? {
        guard let activeSceneID else { return nil }
        return navigator(for: activeSceneID)
    }

    public func navigator(for sceneID: SceneID) -> Navigator? {
        navigators.first { $0.scene.id == sceneID }
    }
}

/// A pending request to open a new window, processed by `WindowOpenerView`.
public struct WindowOpenRequest: Identifiable, Sendable {
    public let id: UUID
    public let windowID: String?

    init(windowID: String?) {
        self.id = UUID()
        self.windowID = windowID
    }
}
