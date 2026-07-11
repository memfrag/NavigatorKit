import SwiftUI

/// Maps route types to view builders, letting features register their
/// destinations without knowing about each other or the app shell.
///
/// One registration per feature populates three things at once: the view
/// mapping, the `Codable` route-type registry (for state restoration), and
/// per-route default placements.
///
/// ```swift
/// let registry = DestinationRegistry {
///     ProductsFeature.destinations
///     ReviewsFeature.destinations
/// }
/// ```
public struct DestinationRegistry {
    private var views: [String: @MainActor (any Route) -> AnyView] = [:]
    private var placements: [String: RoutePlacement] = [:]

    /// The derived `Codable` registry for every registered route type.
    public private(set) var routeTypes = RouteTypeRegistry()

    public init() {}

    public init(@DestinationBuilder _ content: () -> DestinationGroup) {
        self.init()
        add(content())
    }

    /// Adds a feature's destinations to the registry.
    public mutating func add(_ content: some DestinationContent) {
        for entry in content.entries {
            views[entry.typeID] = entry.view
            if let placement = entry.defaultPlacement {
                placements[entry.typeID] = placement
            }
            entry.registerType(&routeTypes)
        }
    }

    /// Whether a destination is registered for the route's type.
    public func hasDestination(for route: AnyRoute) -> Bool {
        views[route.typeID] != nil
    }

    /// Resolves the view for a route. Unknown route types resolve to a
    /// diagnostic placeholder rather than crashing.
    @MainActor
    public func view(for route: AnyRoute) -> AnyView {
        guard let builder = views[route.typeID] else {
            return AnyView(UnregisteredRouteView(typeID: route.typeID))
        }
        return builder(route.base)
    }

    /// The default ``RoutePlacement`` declared for the route's type at
    /// registration, if any.
    public func defaultPlacement(for route: AnyRoute) -> RoutePlacement? {
        placements[route.typeID]
    }
}

/// Shown when a route reaches the UI without a registered destination —
/// a diagnostic aid, not a crash.
struct UnregisteredRouteView: View {
    let typeID: String

    var body: some View {
        ContentUnavailableView {
            Label("Unregistered Route", systemImage: "questionmark.square.dashed")
        } description: {
            Text("No destination is registered for route type “\(typeID)”.")
        }
    }
}
