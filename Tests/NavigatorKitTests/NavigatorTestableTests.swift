import SwiftUI
import Testing

@testable import NavigatorKit

@Suite("Navigator.testable")
@MainActor
struct NavigatorTestableTests {
    @Test func stackConvenienceBuildsRootedScene() {
        let navigator = Navigator.testable(stack: ProductRoute.list)
        #expect(navigator.scene.baseContext.root == AnyRoute(ProductRoute.list))
        #expect(navigator.scene.baseContext.path.isEmpty)
    }

    @Test func appliesIntentsSynchronously() async throws {
        let navigator = Navigator.testable(stack: ProductRoute.list)
        try await navigator.navigate(to: ProductRoute.detail(id: 42), placement: .push)
        #expect(navigator.scene.baseContext.path == [AnyRoute(ProductRoute.detail(id: 42))])
    }

    @Test func honorsRegisteredPlacementDefault() async throws {
        let registry = DestinationRegistry {
            Destination(for: ReviewRoute.self) { _ in Text("review") }
                .placement(.sheet(detents: [.medium]))
        }
        let navigator = Navigator.testable(stack: ProductRoute.list, registry: registry)

        // No explicit placement → the registered .sheet default applies.
        try await navigator.navigate(to: ReviewRoute.compose(productID: 7))

        let sheet = try #require(navigator.scene.baseContext.sheet)
        #expect(sheet.style == .sheet(detents: [.medium]))
        #expect(sheet.content.root == AnyRoute(ReviewRoute.compose(productID: 7)))
    }

    @Test func compoundIntentAcrossContainers() async throws {
        let tabs = TabsLayout(
            selection: TabID("a"),
            tabs: [
                TabDescriptor(id: TabID("a"), title: "A", content: .stack(NavigationContext(root: AnyRoute(ProductRoute.list)))),
                TabDescriptor(id: TabID("b"), title: "B", content: .stack(NavigationContext())),
            ]
        )
        let navigator = Navigator.testable(root: .tabs(tabs))

        try await navigator.perform(
            NavigationIntent {
                SelectTab(TabID("b"))
                Push(ProductRoute.detail(id: 1))
                Present(ReviewRoute.compose(productID: 1))
            }
        )

        #expect(tabs.selection == TabID("b"))
        let base = navigator.scene.baseContext
        #expect(base.path == [AnyRoute(ProductRoute.detail(id: 1))])
        #expect(base.sheet?.content.root == AnyRoute(ReviewRoute.compose(productID: 1)))
    }
}
