import Testing

@testable import NavigatorKit

// Shared fixture tabs
enum AppTab: String {
    case shop, settings, search
}

@MainActor
func makeTabbedScene() -> SceneNavigator {
    let shop = NavigationContext(root: AnyRoute(ProductRoute.list))
    let settingsSplit = SplitLayout(
        sidebarRoot: AnyRoute(SettingsRoute.menu),
        detailContext: NavigationContext()
    )
    let search = NavigationContext()
    return SceneNavigator(
        root: .tabs(
            TabsLayout(
                selection: TabID(AppTab.shop),
                tabs: [
                    TabDescriptor(id: TabID(AppTab.shop), title: "Shop", content: .stack(shop)),
                    TabDescriptor(id: TabID(AppTab.settings), title: "Settings", content: .split(settingsSplit)),
                    TabDescriptor(id: TabID(AppTab.search), title: "Search", role: .search, content: .stack(search)),
                ]
            )
        )
    )
}

enum SettingsRoute: Route {
    case menu, general, advanced
}

@Suite("NavigationContext tree queries")
@MainActor
struct NavigationContextTests {
    @Test func activeLeafWithoutPresentationIsSelf() {
        let context = NavigationContext()
        #expect(context.activeLeaf === context)
        #expect(context.presentationDepth == 0)
    }

    @Test func activeLeafFollowsNestedPresentations() {
        let base = NavigationContext()
        let sheetContent = NavigationContext(root: AnyRoute(ReviewRoute.compose(productID: 1)))
        let nestedContent = NavigationContext()
        base.sheet = PresentedContext(style: .sheet(), content: sheetContent)
        sheetContent.fullScreenCover = PresentedContext(style: .fullScreenCover, content: nestedContent)

        #expect(base.activeLeaf === nestedContent)
        #expect(base.presentationDepth == 2)
        #expect(base.selfAndPresentedDescendants.map(\.id) == [base.id, sheetContent.id, nestedContent.id])
    }

    @Test func sheetTakesPrecedenceOverCover() {
        let base = NavigationContext()
        let sheetContent = NavigationContext()
        let coverContent = NavigationContext()
        base.sheet = PresentedContext(style: .sheet(), content: sheetContent)
        base.fullScreenCover = PresentedContext(style: .fullScreenCover, content: coverContent)
        #expect(base.presented?.content === sheetContent)
    }

    @Test func allRoutesIncludesRootAndPath() {
        let context = NavigationContext(
            root: AnyRoute(ProductRoute.list),
            path: [AnyRoute(ProductRoute.detail(id: 1))]
        )
        #expect(context.allRoutes == [AnyRoute(ProductRoute.list), AnyRoute(ProductRoute.detail(id: 1))])
        #expect(context.containsRoute(AnyRoute(ProductRoute.list)))
        #expect(!context.containsRoute(AnyRoute(ProductRoute.detail(id: 2))))
    }

    @Test func dismissPresentedClearsBothSlots() {
        let base = NavigationContext()
        base.sheet = PresentedContext(style: .sheet(), content: NavigationContext())
        base.fullScreenCover = PresentedContext(style: .fullScreenCover, content: NavigationContext())
        base.dismissPresented()
        #expect(base.presented == nil)
    }
}

@Suite("Transition signaling")
@MainActor
struct TransitionSignalingTests {
    @Test func awaitAppearanceReturnsImmediatelyWhenAppeared() async {
        let context = NavigationContext()
        context.signalDidAppear()
        await context.awaitAppearance()  // must not hang
        #expect(context.hasAppeared)
    }

    @Test func awaitAppearanceSuspendsUntilSignal() async {
        let context = NavigationContext()
        async let waiting: Void = context.awaitAppearance()
        await Task.yield()
        context.signalDidAppear()
        await waiting
        #expect(context.hasAppeared)
    }

    @Test func awaitDisappearanceReturnsImmediatelyWhenNotOnScreen() async {
        let context = NavigationContext()
        await context.awaitDisappearance()  // must not hang
        #expect(!context.hasAppeared)
    }

    @Test func awaitDisappearanceSuspendsUntilSignal() async {
        let context = NavigationContext()
        context.signalDidAppear()
        async let waiting: Void = context.awaitDisappearance()
        await Task.yield()
        context.signalDidDisappear()
        await waiting
        #expect(!context.hasAppeared)
    }
}

@Suite("Layouts and SceneNavigator")
@MainActor
struct SceneNavigatorTests {
    @Test func tabSelectionDrivesPrimaryContext() {
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root else {
            Issue.record("Expected tabs root")
            return
        }
        #expect(scene.baseContext.root == AnyRoute(ProductRoute.list))

        tabs.selection = TabID(AppTab.settings)
        // Settings tab hosts a split: primary context is the detail column.
        guard case .split(let split) = tabs.selectedLayout else {
            Issue.record("Expected split layout in settings tab")
            return
        }
        #expect(scene.baseContext === split.detailContext)
    }

    @Test func activeContextFollowsPresentations() {
        let scene = makeTabbedScene()
        let sheetContent = NavigationContext()
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: sheetContent)
        #expect(scene.activeContext === sheetContent)
    }

    @Test func rootPresentationTakesPrecedence() {
        let scene = makeTabbedScene()
        let onboarding = NavigationContext()
        scene.rootPresentation = PresentedContext(style: .fullScreenCover, content: onboarding)
        #expect(scene.activeContext === onboarding)

        scene.rootPresentation = nil
        #expect(scene.activeContext === scene.baseContext)
    }

    @Test func findRouteSearchesAcrossTabsAndPresentations() {
        let scene = makeTabbedScene()
        scene.baseContext.path = [AnyRoute(ProductRoute.detail(id: 42))]
        let sheetContent = NavigationContext(root: AnyRoute(ReviewRoute.compose(productID: 42)))
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: sheetContent)

        // In the selected tab's path
        let detail = scene.findRoute { $0 == AnyRoute(ProductRoute.detail(id: 42)) }
        #expect(detail?.position == .path(index: 0))
        #expect(detail?.context === scene.baseContext)

        // As a presented context's root
        let review = scene.findRoute { $0.is(ReviewRoute.self) }
        #expect(review?.position == .root)
        #expect(review?.context === sheetContent)

        // In a non-selected tab (sidebar root of the settings split)
        #expect(scene.contains(AnyRoute(SettingsRoute.menu)))
        if case .inSidebar(_, .root) = scene.findRoute(where: { $0 == AnyRoute(SettingsRoute.menu) }) {
        } else {
            Issue.record("Expected sidebar-root location for SettingsRoute.menu")
        }

        // Type-level containment
        #expect(scene.containsRoute(ofType: ProductRoute.self))
        #expect(!scene.containsRoute(ofType: RenamedRoute.self))
    }

    @Test func allContextsIncludesRootPresentationChain() {
        let scene = makeTabbedScene()
        let onboarding = NavigationContext()
        scene.rootPresentation = PresentedContext(style: .sheet(), content: onboarding)
        #expect(scene.allContexts.contains { $0 === onboarding })
        // Base contexts: shop stack, settings detail, search stack — plus onboarding.
        #expect(scene.allContexts.count == 4)
    }
}
