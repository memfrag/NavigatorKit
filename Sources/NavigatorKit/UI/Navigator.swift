import Observation

/// The facade views use to navigate — the only routing API feature views
/// ever see, injected via the environment:
///
/// ```swift
/// @Environment(Navigator.self) private var navigator
///
/// Button("Reviews") {
///     navigator.navigate(to: ReviewRoute.list(productID: id), placement: .sheet())
/// }
/// Button("Done") { navigator.dismiss() }
/// ```
///
/// Every convenience has a fire-and-forget form (for button actions) and an
/// `async throws` form (for callers that await completion or care about
/// errors). Fire-and-forget errors are reported via ``onError``.
@MainActor
@Observable
public final class Navigator {
    /// The scene state this navigator drives.
    public let scene: SceneNavigator

    private let executor: IntentExecutor
    private let registry: DestinationRegistry?

    /// Called when a fire-and-forget operation fails (superseded intents are
    /// not reported). Defaults to a debug print.
    @ObservationIgnored
    public var onError: @MainActor (any Error) -> Void = { error in
        #if DEBUG
            print("NavigatorKit navigation failed: \(error)")
        #endif
    }

    public init(
        scene: SceneNavigator,
        executor: IntentExecutor,
        registry: DestinationRegistry? = nil
    ) {
        self.scene = scene
        self.executor = executor
        self.registry = registry
    }

    /// Creates a navigator with the production UI transition coordinator.
    public convenience init(scene: SceneNavigator, registry: DestinationRegistry? = nil) {
        self.init(
            scene: scene,
            executor: IntentExecutor(transitions: UITransitionCoordinator()),
            registry: registry
        )
    }

    // MARK: - Core

    /// Executes a compound intent, awaiting staged completion.
    public func perform(_ intent: NavigationIntent) async throws {
        try await executor.execute(intent, on: scene)
    }

    /// Fire-and-forget variant of ``perform(_:)``.
    public func perform(_ intent: NavigationIntent) {
        fireAndForget(intent)
    }

    /// Navigates to a single route. Placement resolution: explicit argument →
    /// the route type's registered default → `.push`.
    public func navigate(to route: some Route, placement: RoutePlacement? = nil) async throws {
        try await perform(.navigate(to: route, placement: resolvePlacement(placement, for: AnyRoute(route))))
    }

    /// Fire-and-forget variant of ``navigate(to:placement:)``.
    public func navigate(to route: some Route, placement: RoutePlacement? = nil) {
        fireAndForget(.navigate(to: route, placement: resolvePlacement(placement, for: AnyRoute(route))))
    }

    // MARK: - Conveniences (fire-and-forget)

    /// Pushes onto the deepest active context.
    public func push(_ route: some Route) {
        fireAndForget(NavigationIntent(operations: [.push(AnyRoute(route))]))
    }

    /// Pops one route off the deepest active context.
    public func pop() {
        fireAndForget(NavigationIntent(operations: [.pop]))
    }

    /// Pops the deepest active context to its root.
    public func popToRoot() {
        fireAndForget(NavigationIntent(operations: [.popToRoot]))
    }

    /// Presents a route over the deepest active context.
    public func present(_ route: some Route, style: PresentationStyle = .sheet()) {
        fireAndForget(NavigationIntent(operations: [.present(AnyRoute(route), style: style)]))
    }

    /// Dismisses the deepest presentation.
    public func dismiss() {
        fireAndForget(NavigationIntent(operations: [.dismiss]))
    }

    /// Dismisses every presentation down to the base context.
    public func dismissAll() {
        fireAndForget(NavigationIntent(operations: [.dismissAll]))
    }

    /// Selects a root tab.
    public func select(tab: TabID) {
        fireAndForget(NavigationIntent(operations: [.selectTab(tab)]))
    }

    /// Selects a root tab (string-raw-value enum sugar).
    public func select<T: RawRepresentable>(tab: T) where T.RawValue == String {
        select(tab: TabID(tab))
    }

    /// Sets the sidebar selection of the active split view.
    public func selectSidebar(_ route: (some Route)?) {
        fireAndForget(NavigationIntent(operations: [.selectSidebar(route.map { AnyRoute($0) })]))
    }

    /// Shows an alert on the deepest active context.
    public func alert(_ title: String, message: String? = nil, buttons: [RoutedAlertButton] = []) {
        fireAndForget(
            NavigationIntent(operations: [.alert(RoutedAlert(title, message: message, buttons: buttons))])
        )
    }

    /// Shows a confirmation dialog on the deepest active context.
    public func confirmationDialog(
        _ title: String,
        message: String? = nil,
        buttons: [RoutedAlertButton] = []
    ) {
        fireAndForget(
            NavigationIntent(operations: [.confirmationDialog(RoutedDialog(title, message: message, buttons: buttons))])
        )
    }

    // MARK: - Internals

    private func resolvePlacement(_ explicit: RoutePlacement?, for route: AnyRoute) -> RoutePlacement {
        explicit ?? registry?.defaultPlacement(for: route) ?? .push
    }

    private func fireAndForget(_ intent: NavigationIntent) {
        Task { @MainActor in
            do {
                try await executor.execute(intent, on: scene)
            } catch is CancellationError {
                // Superseded by a newer intent — expected, not an error.
            } catch {
                onError(error)
            }
        }
    }
}
