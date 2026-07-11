import Testing

@testable import NavigatorKit

@MainActor
private func plan(_ scene: SceneNavigator, @NavigationIntentBuilder _ build: () -> [NavigationOperation]) throws -> ExecutionPlan {
    try Planner.plan(NavigationIntent(build), in: scene)
}

@MainActor
private func stageKinds(of plan: ExecutionPlan) -> [ExecutionStage.Kind] {
    plan.stages.map(\.kind)
}

@Suite("Planner staging")
@MainActor
struct PlannerStagingTests {
    @Test func pushProducesSingleBaseStage() throws {
        let scene = makeTabbedScene()
        let plan = try plan(scene) { Push(ProductRoute.detail(id: 1)) }
        #expect(stageKinds(of: plan) == [.base])
    }

    @Test func canonicalHardIntentStages() throws {
        // tab switch + stack set + sheet + push inside sheet + alert
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root else { return }
        tabs.selection = TabID(AppTab.search)

        let plan = try plan(scene) {
            SelectTab(AppTab.shop)
            SetStack(ProductRoute.list, ProductRoute.detail(id: 42))
            Present(ReviewRoute.compose(productID: 42), style: .sheet(detents: [.medium]))
            Push(ProductRoute.detail(id: 1))
            Alert("Thanks!")
        }
        // Push inside the fresh sheet folds into its construction — no extra stage.
        #expect(stageKinds(of: plan) == [.base, .present, .overlay])
    }

    @Test func nestedPresentsGetOneStageEach() throws {
        let scene = makeTabbedScene()
        let plan = try plan(scene) {
            Present(ReviewRoute.compose(productID: 1))
            Present(ProductRoute.detail(id: 2), style: .fullScreenCover)
        }
        #expect(stageKinds(of: plan) == [.present, .present])
    }

    @Test func tabSwitchWithVisibleSheetEmitsDismissFirst() throws {
        let scene = makeTabbedScene()
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: NavigationContext())

        let plan = try plan(scene) {
            SelectTab(AppTab.search)
        }
        #expect(stageKinds(of: plan) == [.dismiss, .base])
    }

    @Test func reselectingCurrentTabKeepsItsSheet() throws {
        let scene = makeTabbedScene()
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: NavigationContext())

        let plan = try plan(scene) {
            SelectTab(AppTab.shop)
        }
        #expect(stageKinds(of: plan) == [.base])
    }

    @Test func pathMutationUnderSheetDismissesIt() throws {
        let scene = makeTabbedScene()
        let sheetContent = NavigationContext()
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: sheetContent)

        // Cursor starts at the sheet content (active leaf); selecting the
        // same tab retargets to the base, so the set-path conflicts with the
        // sheet above it.
        let plan = try plan(scene) {
            SelectTab(AppTab.shop)
            SetStack(ProductRoute.detail(id: 9))
        }
        #expect(stageKinds(of: plan) == [.dismiss, .base])
    }

    @Test func popToMissingRouteThrows() throws {
        let scene = makeTabbedScene()
        #expect(throws: NavigationError.routeNotInPath(AnyRoute(ProductRoute.detail(id: 5)))) {
            try Planner.plan(
                NavigationIntent { PopTo(ProductRoute.detail(id: 5)) },
                in: scene
            )
        }
    }

    @Test func selectTabOnStackRootThrows() throws {
        let scene = SceneNavigator(root: .stack(NavigationContext()))
        #expect(throws: NavigationError.noTabsLayout) {
            try Planner.plan(NavigationIntent { SelectTab(AppTab.shop) }, in: scene)
        }
    }

    @Test func unknownTabThrows() throws {
        let scene = makeTabbedScene()
        #expect(throws: NavigationError.unknownTab(TabID("bogus"))) {
            try Planner.plan(NavigationIntent { SelectTab(TabID("bogus")) }, in: scene)
        }
    }

    @Test func dismissAfterPresentThrows() throws {
        let scene = makeTabbedScene()
        #expect(throws: NavigationError.invalidOperation("dismiss cannot follow present within a single intent")) {
            try Planner.plan(
                NavigationIntent {
                    Present(ReviewRoute.compose(productID: 1))
                    Dismiss()
                },
                in: scene
            )
        }
    }

    @Test func selectSidebarWithoutSplitThrows() throws {
        let scene = SceneNavigator(root: .stack(NavigationContext()))
        #expect(throws: NavigationError.noSplitLayout) {
            try Planner.plan(
                NavigationIntent { SelectSidebar(SettingsRoute.general) },
                in: scene
            )
        }
    }
}
