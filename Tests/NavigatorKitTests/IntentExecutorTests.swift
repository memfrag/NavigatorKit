import Testing

@testable import NavigatorKit

/// Records the order of stage kinds it was asked to settle.
@MainActor
final class RecordingTransitionCoordinator: TransitionCoordinator {
    private(set) var settledKinds: [ExecutionStage.Kind] = []

    func settle(after stage: ExecutionStage, in scene: SceneNavigator) async throws {
        settledKinds.append(stage.kind)
    }
}

/// Suspends in `settle` until released — for cancellation tests.
@MainActor
final class GatedTransitionCoordinator: TransitionCoordinator {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var settleCount = 0

    func settle(after stage: ExecutionStage, in scene: SceneNavigator) async throws {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            settleCount += 1
        }
        try Task.checkCancellation()
    }

    func releaseAll() {
        let released = waiters
        waiters = []
        for waiter in released { waiter.resume() }
    }
}

@MainActor
private func makeExecutor() -> (IntentExecutor, RecordingTransitionCoordinator) {
    let recorder = RecordingTransitionCoordinator()
    return (IntentExecutor(transitions: recorder), recorder)
}

@Suite("IntentExecutor end states")
@MainActor
struct IntentExecutorTests {
    @Test func canonicalHardIntentEndState() async throws {
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root else { return }
        tabs.selection = TabID(AppTab.search)
        let (executor, recorder) = makeExecutor()

        try await executor.execute(
            NavigationIntent {
                SelectTab(AppTab.shop)
                SetStack(ProductRoute.list, ProductRoute.detail(id: 42))
                Present(ReviewRoute.compose(productID: 42), style: .sheet(detents: [.medium]))
                Push(ProductRoute.detail(id: 1))
                Alert("Thanks!", message: "Draft restored.")
            },
            on: scene
        )

        #expect(tabs.selection == TabID(AppTab.shop))
        let base = scene.baseContext
        #expect(base.path == [AnyRoute(ProductRoute.list), AnyRoute(ProductRoute.detail(id: 42))])

        let sheet = try #require(base.sheet)
        #expect(sheet.style == .sheet(detents: [.medium]))
        #expect(sheet.content.root == AnyRoute(ReviewRoute.compose(productID: 42)))
        #expect(sheet.content.path == [AnyRoute(ProductRoute.detail(id: 1))])
        #expect(sheet.content.alert?.title == "Thanks!")

        #expect(recorder.settledKinds == [.base, .present, .overlay])
    }

    @Test func nestedPresentation() async throws {
        let scene = makeTabbedScene()
        let (executor, recorder) = makeExecutor()

        try await executor.execute(
            NavigationIntent {
                Present(ReviewRoute.compose(productID: 1))
                Present(ProductRoute.detail(id: 2), style: .fullScreenCover)
            },
            on: scene
        )

        let sheet = try #require(scene.baseContext.sheet)
        let nested = try #require(sheet.content.fullScreenCover)
        #expect(nested.content.root == AnyRoute(ProductRoute.detail(id: 2)))
        #expect(scene.activeContext === nested.content)
        #expect(recorder.settledKinds == [.present, .present])
    }

    @Test func tabSwitchDismissesVisibleSheetButKeepsSiblingStacks() async throws {
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root else { return }
        let shopBase = scene.baseContext
        shopBase.path = [AnyRoute(ProductRoute.detail(id: 7))]
        shopBase.sheet = PresentedContext(style: .sheet(), content: NavigationContext())
        let (executor, _) = makeExecutor()

        try await executor.execute(NavigationIntent { SelectTab(AppTab.search) }, on: scene)

        #expect(tabs.selection == TabID(AppTab.search))
        // Visible sheet dismissed (window-global), sibling stack untouched.
        #expect(shopBase.sheet == nil)
        #expect(shopBase.path == [AnyRoute(ProductRoute.detail(id: 7))])
    }

    @Test func dismissRemovesDeepestPresentation() async throws {
        let scene = makeTabbedScene()
        let sheetContent = NavigationContext()
        let nestedContent = NavigationContext()
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: sheetContent)
        sheetContent.sheet = PresentedContext(style: .sheet(), content: nestedContent)
        let (executor, _) = makeExecutor()

        try await executor.execute(NavigationIntent { Dismiss() }, on: scene)

        #expect(scene.baseContext.sheet != nil)
        #expect(sheetContent.sheet == nil)

        try await executor.execute(NavigationIntent { Dismiss() }, on: scene)
        #expect(scene.baseContext.sheet == nil)

        // Nothing presented: no-op, no error.
        try await executor.execute(NavigationIntent { Dismiss() }, on: scene)
    }

    @Test func dismissAllUnwindsRootPresentationAndBaseChain() async throws {
        let scene = makeTabbedScene()
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: NavigationContext())
        scene.rootPresentation = PresentedContext(style: .fullScreenCover, content: NavigationContext())
        let (executor, _) = makeExecutor()

        try await executor.execute(NavigationIntent { DismissAll() }, on: scene)

        #expect(scene.rootPresentation == nil)
        #expect(scene.baseContext.sheet == nil)
    }

    @Test func popOperations() async throws {
        let scene = makeTabbedScene()
        scene.baseContext.path = [
            AnyRoute(ProductRoute.detail(id: 1)),
            AnyRoute(ProductRoute.detail(id: 2)),
            AnyRoute(ProductRoute.detail(id: 3)),
        ]
        let (executor, _) = makeExecutor()

        try await executor.execute(NavigationIntent { Pop() }, on: scene)
        #expect(scene.baseContext.path.count == 2)

        try await executor.execute(NavigationIntent { PopTo(ProductRoute.detail(id: 1)) }, on: scene)
        #expect(scene.baseContext.path == [AnyRoute(ProductRoute.detail(id: 1))])

        try await executor.execute(NavigationIntent { PopToRoot() }, on: scene)
        #expect(scene.baseContext.path.isEmpty)

        // Pop on an empty stack is a no-op.
        try await executor.execute(NavigationIntent { Pop() }, on: scene)
        #expect(scene.baseContext.path.isEmpty)
    }

    @Test func selectSidebarTargetsDetail() async throws {
        let scene = makeTabbedScene()
        let (executor, _) = makeExecutor()

        try await executor.execute(
            NavigationIntent {
                SelectTab(AppTab.settings)
                SelectSidebar(SettingsRoute.general)
                Push(SettingsRoute.advanced)
            },
            on: scene
        )

        guard case .tabs(let tabs) = scene.root,
            case .split(let split) = tabs.selectedLayout
        else {
            Issue.record("Expected settings split")
            return
        }
        #expect(split.sidebarSelection == AnyRoute(SettingsRoute.general))
        #expect(split.detailContext.path == [AnyRoute(SettingsRoute.advanced)])
    }

    @Test func sidebarSelectionChangeDismissesDetailSheet() async throws {
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root,
            case .split(let split) = tabs.layout(for: TabID(AppTab.settings))
        else {
            Issue.record("Expected settings split")
            return
        }
        split.sidebarSelection = AnyRoute(SettingsRoute.general)
        split.detailContext.sheet = PresentedContext(style: .sheet(), content: NavigationContext())
        let (executor, _) = makeExecutor()

        try await executor.execute(
            NavigationIntent {
                SelectTab(AppTab.settings)
                SelectSidebar(SettingsRoute.advanced)
            },
            on: scene
        )
        #expect(split.detailContext.sheet == nil)
    }
}

@Suite("Activate semantics")
@MainActor
struct ActivateTests {
    @Test func activatesRouteInOtherTabDismissingCoverings() async throws {
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root else { return }
        // Shop tab: [detail(1), detail(2)], with a sheet over it.
        let shopBase = scene.baseContext
        shopBase.path = [AnyRoute(ProductRoute.detail(id: 1)), AnyRoute(ProductRoute.detail(id: 2))]
        shopBase.sheet = PresentedContext(style: .sheet(), content: NavigationContext())
        // Move away to search.
        tabs.selection = TabID(AppTab.search)
        let (executor, _) = makeExecutor()

        try await executor.execute(
            .navigate(to: ProductRoute.detail(id: 1), placement: .activateExisting(else: .push)),
            on: scene
        )

        #expect(tabs.selection == TabID(AppTab.shop))
        #expect(shopBase.path == [AnyRoute(ProductRoute.detail(id: 1))])
        #expect(shopBase.sheet == nil)
    }

    @Test func activateFallsBackWhenAbsent() async throws {
        let scene = makeTabbedScene()
        let (executor, _) = makeExecutor()

        try await executor.execute(
            .navigate(to: ProductRoute.detail(id: 99), placement: .activateExisting(else: .push)),
            on: scene
        )
        #expect(scene.baseContext.path == [AnyRoute(ProductRoute.detail(id: 99))])
    }

    @Test func activateRouteAtContextRootPopsToRoot() async throws {
        let scene = makeTabbedScene()
        scene.baseContext.path = [AnyRoute(ProductRoute.detail(id: 1))]
        let (executor, _) = makeExecutor()

        // ProductRoute.list is the shop tab's root.
        try await executor.execute(
            .navigate(to: ProductRoute.list, placement: .activateExisting(else: .push)),
            on: scene
        )
        #expect(scene.baseContext.path.isEmpty)
    }

    @Test func activateRouteInsideSheetKeepsSheet() async throws {
        let scene = makeTabbedScene()
        let sheetContent = NavigationContext(root: AnyRoute(ReviewRoute.compose(productID: 5)))
        sheetContent.path = [AnyRoute(ProductRoute.detail(id: 8))]
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: sheetContent)
        let (executor, _) = makeExecutor()

        try await executor.execute(
            .navigate(to: ReviewRoute.compose(productID: 5), placement: .activateExisting(else: .push)),
            on: scene
        )

        // The sheet containing the route stays; the stack above it pops.
        #expect(scene.baseContext.sheet != nil)
        #expect(sheetContent.path.isEmpty)
    }

    @Test func placementMappings() {
        #expect(NavigationIntent.navigate(to: ProductRoute.list).operations.count == 1)
        if case .push = NavigationIntent.navigate(to: ProductRoute.list, placement: .push).operations[0] {
        } else { Issue.record("Expected push op") }
        if case .setPath(let path) = NavigationIntent.navigate(to: ProductRoute.list, placement: .replaceStack).operations[0] {
            #expect(path == [AnyRoute(ProductRoute.list)])
        } else { Issue.record("Expected setPath op") }
        if case .present(_, let style) = NavigationIntent.navigate(to: ProductRoute.list, placement: .sheet(detents: [.medium])).operations[0] {
            #expect(style == .sheet(detents: [.medium]))
        } else { Issue.record("Expected present op") }
        if case .activate = NavigationIntent.navigate(to: ProductRoute.list, placement: .activateExisting(else: .push)).operations[0] {
        } else { Issue.record("Expected activate op") }
    }
}

@Suite("Executor serialization")
@MainActor
struct ExecutorSerializationTests {
    @Test func newIntentCancelsInFlightOne() async throws {
        let scene = makeTabbedScene()
        let gate = GatedTransitionCoordinator()
        let executor = IntentExecutor(transitions: gate)

        let first = Task {
            try await executor.execute(
                NavigationIntent {
                    Present(ReviewRoute.compose(productID: 1))
                    Present(ProductRoute.detail(id: 2))
                },
                on: scene
            )
        }
        // Let the first intent apply its first present stage and block in settle.
        while gate.settleCount == 0 { await Task.yield() }

        let second = Task {
            try await executor.execute(
                NavigationIntent {
                    SelectTab(AppTab.shop)
                    Push(ProductRoute.detail(id: 3))
                },
                on: scene
            )
        }
        await Task.yield()
        gate.releaseAll()

        // First was superseded mid-plan: its first present applied, the
        // second never did.
        await #expect(throws: CancellationError.self) { try await first.value }

        // Second plans against the partial state (sheet up from the aborted
        // intent) and dismisses it: stages are [dismiss, base].
        while gate.settleCount < 2 { await Task.yield() }
        gate.releaseAll()
        while gate.settleCount < 3 { await Task.yield() }
        gate.releaseAll()
        try await second.value

        #expect(scene.baseContext.sheet == nil)
        #expect(scene.baseContext.path == [AnyRoute(ProductRoute.detail(id: 3))])
    }
}
