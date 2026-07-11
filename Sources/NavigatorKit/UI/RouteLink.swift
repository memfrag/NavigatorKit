import SwiftUI

/// A `NavigationLink` that pushes a ``Route`` — the value-based link for
/// routed stacks, resolved through the destination registry.
///
/// ```swift
/// RouteLink(ProductRoute.detail(id: product.id)) {
///     ProductRowView(product: product)
/// }
/// ```
public struct RouteLink<Label: View>: View {
    private let route: AnyRoute
    private let label: Label

    public init(_ route: some Route, @ViewBuilder label: () -> Label) {
        self.route = AnyRoute(route)
        self.label = label()
    }

    public var body: some View {
        NavigationLink(value: route) {
            label
        }
    }
}

extension RouteLink where Label == Text {
    public init(_ title: some StringProtocol, route: some Route) {
        self.init(route) { Text(title) }
    }
}
