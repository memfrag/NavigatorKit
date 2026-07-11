import SwiftUI

/// Anything that contributes destination registrations — a single
/// ``Destination`` or a composed ``DestinationGroup``.
public protocol DestinationContent {
    var entries: [DestinationEntry] { get }
}

/// One route type's registration: its view builder, `Codable` registration,
/// and optional default placement.
public struct DestinationEntry {
    let typeID: String
    let registerType: (inout RouteTypeRegistry) -> Void
    let view: @MainActor (any Route) -> AnyView
    let defaultPlacement: RoutePlacement?
}

/// Declares the view mapping for one route type.
///
/// ```swift
/// Destination(for: ProductRoute.self) { route in
///     switch route {
///     case .list: ProductListView()
///     case .detail(let id): ProductDetailView(id: id)
///     }
/// }
/// ```
public struct Destination<R: Route>: DestinationContent {
    private let builder: @MainActor (R) -> AnyView
    private var defaultPlacement: RoutePlacement?

    public init(
        for type: R.Type = R.self,
        @ViewBuilder content: @escaping @MainActor (R) -> some View
    ) {
        self.builder = { AnyView(content($0)) }
    }

    /// Declares the default ``RoutePlacement`` used when `navigate(to:)` is
    /// called for this route type without an explicit placement.
    public func placement(_ placement: RoutePlacement) -> Destination {
        var copy = self
        copy.defaultPlacement = placement
        return copy
    }

    public var entries: [DestinationEntry] {
        let builder = builder
        return [
            DestinationEntry(
                typeID: R.routeTypeID,
                registerType: { $0.register(R.self) },
                view: { route in
                    guard let typed = route as? R else {
                        return AnyView(UnregisteredRouteView(typeID: R.routeTypeID))
                    }
                    return builder(typed)
                },
                defaultPlacement: defaultPlacement
            )
        ]
    }
}

/// A flattened collection of destination registrations.
public struct DestinationGroup: DestinationContent {
    public let entries: [DestinationEntry]

    public init(entries: [DestinationEntry]) {
        self.entries = entries
    }
}

/// Result builder composing ``DestinationContent`` values.
@resultBuilder
public enum DestinationBuilder {
    public static func buildExpression(_ expression: some DestinationContent) -> DestinationGroup {
        DestinationGroup(entries: expression.entries)
    }

    public static func buildBlock(_ components: DestinationGroup...) -> DestinationGroup {
        DestinationGroup(entries: components.flatMap(\.entries))
    }

    public static func buildOptional(_ component: DestinationGroup?) -> DestinationGroup {
        component ?? DestinationGroup(entries: [])
    }

    public static func buildEither(first component: DestinationGroup) -> DestinationGroup {
        component
    }

    public static func buildEither(second component: DestinationGroup) -> DestinationGroup {
        component
    }

    public static func buildArray(_ components: [DestinationGroup]) -> DestinationGroup {
        DestinationGroup(entries: components.flatMap(\.entries))
    }
}
