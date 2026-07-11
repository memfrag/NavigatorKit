import SwiftUI
import Testing

@testable import NavigatorKit

private struct ProductsFeature: RoutableFeature {
    static var destinations: DestinationGroup {
        Destination(for: ProductRoute.self) { route in
            switch route {
            case .list: Text("list")
            case .detail(let id): Text("detail \(id)")
            }
        }
    }
}

private struct ReviewsFeature: RoutableFeature {
    static var destinations: DestinationGroup {
        Destination(for: ReviewRoute.self) { _ in
            Text("review")
        }
        .placement(.sheet(detents: [.medium]))
    }
}

@Suite("DestinationRegistry")
@MainActor
struct DestinationRegistryTests {
    private var registry: DestinationRegistry {
        DestinationRegistry {
            ProductsFeature.destinations
            ReviewsFeature.destinations
        }
    }

    @Test func registersViewsForAllFeatures() {
        let registry = registry
        #expect(registry.hasDestination(for: AnyRoute(ProductRoute.list)))
        #expect(registry.hasDestination(for: AnyRoute(ReviewRoute.compose(productID: 1))))
        #expect(!registry.hasDestination(for: AnyRoute(RenamedRoute(value: "x"))))
    }

    @Test func derivesRouteTypeRegistryForCoding() throws {
        let registry = registry
        #expect(registry.routeTypes.contains("ProductRoute"))
        #expect(registry.routeTypes.contains("ReviewRoute"))

        // Round-trip an AnyRoute using only the derived registry.
        let data = try JSONEncoder().encode(AnyRoute(ProductRoute.detail(id: 3)))
        let decoded = try registry.routeTypes.jsonDecoder().decode(AnyRoute.self, from: data)
        #expect(decoded == AnyRoute(ProductRoute.detail(id: 3)))
    }

    @Test func placementDefaults() {
        let registry = registry
        if case .present(let style)? = registry.defaultPlacement(for: AnyRoute(ReviewRoute.compose(productID: 1))) {
            #expect(style == .sheet(detents: [.medium]))
        } else {
            Issue.record("Expected registered sheet placement for ReviewRoute")
        }
        #expect(registry.defaultPlacement(for: AnyRoute(ProductRoute.list)) == nil)
    }

    @Test func navigatorUsesRegisteredPlacementDefault() async throws {
        let scene = makeTabbedScene()
        let navigator = Navigator(
            scene: scene,
            executor: IntentExecutor(transitions: ImmediateTransitionCoordinator()),
            registry: registry
        )

        // No explicit placement: ReviewRoute's registered default (sheet) applies.
        try await navigator.navigate(to: ReviewRoute.compose(productID: 9))
        let sheet = try #require(scene.baseContext.sheet)
        #expect(sheet.content.root == AnyRoute(ReviewRoute.compose(productID: 9)))
        #expect(sheet.style == .sheet(detents: [.medium]))

        // Unregistered placement: falls back to push — onto the active leaf,
        // which is now the sheet's content.
        try await navigator.navigate(to: ProductRoute.detail(id: 5))
        #expect(sheet.content.path == [AnyRoute(ProductRoute.detail(id: 5))])
        #expect(scene.baseContext.path.isEmpty)
    }
}
