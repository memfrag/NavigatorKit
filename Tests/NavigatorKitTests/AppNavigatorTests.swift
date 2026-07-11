import Foundation
import Testing

@testable import NavigatorKit

@MainActor
private func makeAppNavigator(
    policy: any SceneSelectionPolicy = ReuseActiveScenePolicy()
) -> AppNavigator {
    AppNavigator(
        destinations: DestinationRegistry(),
        deepLinks: DeepLinkMap {
            URLPattern("/products/:id") { params in
                try NavigationIntent {
                    SelectTab(AppTab.shop)
                    SetStack(ProductRoute.list, ProductRoute.detail(id: try params.id(Int.self)))
                }
            }
        },
        scenePolicy: policy
    )
}

@MainActor
private func makeSceneNavigatorPair() -> Navigator {
    Navigator(
        scene: makeTabbedScene(),
        executor: IntentExecutor(transitions: ImmediateTransitionCoordinator())
    )
}

@MainActor
private func settle() async {
    // Fire-and-forget intents hop through one Task; drain the main queue.
    for _ in 0..<20 { await Task.yield() }
}

@Suite("AppNavigator")
@MainActor
struct AppNavigatorTests {
    @Test func coldLaunchParksIntentUntilFirstSceneRegisters() async throws {
        let app = makeAppNavigator()

        app.open(URL(string: "shopapp://products/42")!)
        #expect(!app.mailbox.isEmpty)

        let navigator = makeSceneNavigatorPair()
        let claimed = try #require(app.register(navigator))
        try await navigator.perform(claimed)

        #expect(navigator.scene.baseContext.path.last == AnyRoute(ProductRoute.detail(id: 42)))
        #expect(app.mailbox.isEmpty)
        #expect(app.activeSceneID == navigator.scene.id)
    }

    @Test func openRoutesToActiveScene() async throws {
        let app = makeAppNavigator()
        let first = makeSceneNavigatorPair()
        let second = makeSceneNavigatorPair()
        _ = app.register(first)
        _ = app.register(second)
        app.sceneDidBecomeActive(second.scene.id)

        app.open(URL(string: "shopapp://products/7")!)
        await settle()

        #expect(second.scene.baseContext.path.last == AnyRoute(ProductRoute.detail(id: 7)))
        #expect(first.scene.baseContext.path.isEmpty)
    }

    @Test func unhandledURLInvokesHook() {
        let app = makeAppNavigator()
        let navigator = makeSceneNavigatorPair()
        _ = app.register(navigator)

        var unhandled: URL?
        app.onUnhandledURL = { unhandled = $0 }
        app.open(URL(string: "shopapp://nope")!)
        #expect(unhandled == URL(string: "shopapp://nope"))
    }

    @Test func reuseSceneShowingRoutePolicyPicksMatchingScene() async throws {
        let app = makeAppNavigator(policy: ReuseSceneShowingRoutePolicy())
        let first = makeSceneNavigatorPair()
        let second = makeSceneNavigatorPair()
        _ = app.register(first)
        _ = app.register(second)
        app.sceneDidBecomeActive(first.scene.id)

        // Second scene already shows detail(9); the deep link should reuse it
        // even though the first scene is active. The absolute intent then
        // sets that scene's stack.
        second.scene.baseContext.path = [AnyRoute(ProductRoute.detail(id: 9))]
        app.open(URL(string: "shopapp://products/9")!)
        await settle()

        #expect(
            second.scene.baseContext.path
                == [AnyRoute(ProductRoute.list), AnyRoute(ProductRoute.detail(id: 9))]
        )
        #expect(first.scene.baseContext.path.isEmpty)
    }

    @Test func reusePolicyMatchesByRouteTypeWhenNoExactMatch() {
        let policy = ReuseSceneShowingRoutePolicy()
        let plain = SceneNavigator(root: .stack(NavigationContext()))
        let withReview = SceneNavigator(root: .stack(NavigationContext()))
        withReview.baseContext.sheet = PresentedContext(
            style: .sheet(),
            content: NavigationContext(root: AnyRoute(ReviewRoute.compose(productID: 5)))
        )

        // No scene shows compose(9) exactly, but `withReview` shows a
        // ReviewRoute → type-level reuse.
        let decision = policy.decide(
            intent: NavigationIntent { Push(ReviewRoute.compose(productID: 9)) },
            url: nil,
            scenes: [plain, withReview],
            activeSceneID: plain.id
        )
        guard case .use(let id) = decision else {
            Issue.record("Expected .use, got \(decision)")
            return
        }
        #expect(id == withReview.id)

        // No route of that type anywhere: fallback (default .useActive).
        let fallback = policy.decide(
            intent: NavigationIntent { Push(SettingsRoute.advanced) },
            url: nil,
            scenes: [plain, withReview],
            activeSceneID: plain.id
        )
        guard case .useActive = fallback else {
            Issue.record("Expected .useActive, got \(fallback)")
            return
        }
    }

    @Test func newWindowPreferenceParksIntentAndRequestsWindow() async throws {
        let app = makeAppNavigator()
        let first = makeSceneNavigatorPair()
        _ = app.register(first)

        app.perform(
            NavigationIntent { Push(ProductRoute.detail(id: 5)) },
            scenePreference: .newWindow(windowID: "main")
        )

        #expect(app.pendingWindowRequests.count == 1)
        #expect(app.pendingWindowRequests[0].windowID == "main")
        #expect(!app.mailbox.isEmpty)
        #expect(first.scene.baseContext.path.isEmpty)

        // The freshly opened window's scene registers and claims the intent.
        let newWindow = makeSceneNavigatorPair()
        let claimed = try #require(app.register(newWindow))
        try await newWindow.perform(claimed)
        #expect(newWindow.scene.baseContext.path.last == AnyRoute(ProductRoute.detail(id: 5)))
    }

    @Test func noMultiWindowFallbackRunsInCurrentScene() async throws {
        let app = makeAppNavigator()
        let only = makeSceneNavigatorPair()
        _ = app.register(only)

        app.perform(
            NavigationIntent { Push(ProductRoute.detail(id: 6)) },
            scenePreference: .newWindow()
        )
        let request = try #require(app.pendingWindowRequests.first)

        // Simulates WindowOpenerView on a platform without multi-window.
        app.consumeWindowRequest(request, openedWindow: false, fallback: only)
        await settle()

        #expect(app.pendingWindowRequests.isEmpty)
        #expect(only.scene.baseContext.path.last == AnyRoute(ProductRoute.detail(id: 6)))
    }

    @Test func unregisterReassignsActiveScene() {
        let app = makeAppNavigator()
        let first = makeSceneNavigatorPair()
        let second = makeSceneNavigatorPair()
        _ = app.register(first)
        _ = app.register(second)
        app.sceneDidBecomeActive(second.scene.id)

        app.unregister(sceneID: second.scene.id)
        #expect(app.navigators.count == 1)
        #expect(app.activeSceneID == first.scene.id)
    }
}
