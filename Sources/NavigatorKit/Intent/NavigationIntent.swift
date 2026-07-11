/// A complete, declarative navigation destination: an ordered list of
/// ``NavigationOperation``s produced by hand or via the intent builder DSL.
///
/// ```swift
/// let intent = NavigationIntent {
///     SelectTab(AppTab.shop)
///     SetStack(ProductRoute.list, ProductRoute.detail(id: 42))
///     Present(ReviewRoute.compose(productID: 42), style: .sheet(detents: [.medium]))
///     Alert("Thanks!", message: "Your review draft was restored.")
/// }
/// ```
public struct NavigationIntent: Sendable {
    public var operations: [NavigationOperation]

    public init(operations: [NavigationOperation]) {
        self.operations = operations
    }

    public init(@NavigationIntentBuilder _ build: () -> [NavigationOperation]) {
        self.operations = build()
    }
}

extension NavigationIntent {
    /// The intent equivalent of `navigate(to:placement:)`: a single-route
    /// destination with explicit placement semantics.
    public static func navigate(
        to route: some Route,
        placement: RoutePlacement = .push
    ) -> NavigationIntent {
        let anyRoute = AnyRoute(route)
        let operations: [NavigationOperation] =
            switch placement {
            case .push: [.push(anyRoute)]
            case .replaceStack: [.setPath([anyRoute])]
            case .present(let style): [.present(anyRoute, style: style)]
            case .activateExisting(let fallback): [.activate(anyRoute, fallback: fallback)]
            }
        return NavigationIntent(operations: operations)
    }
}

// MARK: - Result builder

@resultBuilder
public enum NavigationIntentBuilder {
    public static func buildExpression(_ expression: some IntentOperationConvertible) -> [NavigationOperation] {
        expression.intentOperations
    }

    public static func buildBlock(_ components: [NavigationOperation]...) -> [NavigationOperation] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [NavigationOperation]?) -> [NavigationOperation] {
        component ?? []
    }

    public static func buildEither(first component: [NavigationOperation]) -> [NavigationOperation] {
        component
    }

    public static func buildEither(second component: [NavigationOperation]) -> [NavigationOperation] {
        component
    }

    public static func buildArray(_ components: [[NavigationOperation]]) -> [NavigationOperation] {
        components.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ component: [NavigationOperation]) -> [NavigationOperation] {
        component
    }
}

/// Anything that contributes operations to a ``NavigationIntent`` built with
/// the DSL — the `SelectTab` / `SetStack` / `Present` / … wrapper structs,
/// or a raw ``NavigationOperation``.
public protocol IntentOperationConvertible {
    var intentOperations: [NavigationOperation] { get }
}

extension NavigationOperation: IntentOperationConvertible {
    public var intentOperations: [NavigationOperation] { [self] }
}

// MARK: - DSL operations

/// Selects a tab at the scene root.
public struct SelectTab: IntentOperationConvertible {
    let tab: TabID

    public init(_ tab: TabID) { self.tab = tab }

    public init<T: RawRepresentable>(_ tab: T) where T.RawValue == String {
        self.tab = TabID(tab)
    }

    public var intentOperations: [NavigationOperation] { [.selectTab(tab)] }
}

/// Sets the sidebar selection of the current split view.
public struct SelectSidebar: IntentOperationConvertible {
    let selection: AnyRoute?

    public init(_ selection: (some Route)?) {
        self.selection = selection.map(AnyRoute.init)
    }

    public var intentOperations: [NavigationOperation] { [.selectSidebar(selection)] }
}

/// Replaces the current context's stack path with the given routes.
public struct SetStack: IntentOperationConvertible {
    let routes: [AnyRoute]

    public init(_ routes: any Route...) {
        self.routes = routes.map { AnyRoute($0) }
    }

    public init(_ routes: [AnyRoute]) {
        self.routes = routes
    }

    public var intentOperations: [NavigationOperation] { [.setPath(routes)] }
}

/// Pushes a route onto the current context's stack.
public struct Push: IntentOperationConvertible {
    let route: AnyRoute

    public init(_ route: some Route) { self.route = AnyRoute(route) }

    public var intentOperations: [NavigationOperation] { [.push(route)] }
}

/// Pops one route off the current context's stack.
public struct Pop: IntentOperationConvertible {
    public init() {}
    public var intentOperations: [NavigationOperation] { [.pop] }
}

/// Pops the current context's stack to its root.
public struct PopToRoot: IntentOperationConvertible {
    public init() {}
    public var intentOperations: [NavigationOperation] { [.popToRoot] }
}

/// Pops to the last occurrence of the given route in the current stack.
public struct PopTo: IntentOperationConvertible {
    let route: AnyRoute

    public init(_ route: some Route) { self.route = AnyRoute(route) }

    public var intentOperations: [NavigationOperation] { [.popTo(route)] }
}

/// Presents a route over the current context; subsequent operations apply
/// inside the presented context.
public struct Present: IntentOperationConvertible {
    let route: AnyRoute
    let style: PresentationStyle

    public init(_ route: some Route, style: PresentationStyle = .sheet()) {
        self.route = AnyRoute(route)
        self.style = style
    }

    public var intentOperations: [NavigationOperation] { [.present(route, style: style)] }
}

/// Dismisses the deepest presentation in the scene.
public struct Dismiss: IntentOperationConvertible {
    public init() {}
    public var intentOperations: [NavigationOperation] { [.dismiss] }
}

/// Dismisses every presentation down to the current base context.
public struct DismissAll: IntentOperationConvertible {
    public init() {}
    public var intentOperations: [NavigationOperation] { [.dismissAll] }
}

/// Shows an alert on the current context.
public struct Alert: IntentOperationConvertible {
    let alert: RoutedAlert

    public init(_ title: String, message: String? = nil, buttons: [RoutedAlertButton] = []) {
        self.alert = RoutedAlert(title, message: message, buttons: buttons)
    }

    public init(_ alert: RoutedAlert) { self.alert = alert }

    public var intentOperations: [NavigationOperation] { [.alert(alert)] }
}

/// Shows a confirmation dialog on the current context.
public struct Dialog: IntentOperationConvertible {
    let dialog: RoutedDialog

    public init(_ title: String, message: String? = nil, buttons: [RoutedAlertButton] = []) {
        self.dialog = RoutedDialog(title, message: message, buttons: buttons)
    }

    public init(_ dialog: RoutedDialog) { self.dialog = dialog }

    public var intentOperations: [NavigationOperation] { [.confirmationDialog(dialog)] }
}

/// Reveals an existing instance of the route, or applies the fallback.
public struct Activate: IntentOperationConvertible {
    let route: AnyRoute
    let fallback: ActivationFallback

    public init(_ route: some Route, fallback: ActivationFallback = .push) {
        self.route = AnyRoute(route)
        self.fallback = fallback
    }

    public var intentOperations: [NavigationOperation] { [.activate(route, fallback: fallback)] }
}
