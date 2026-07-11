import Foundation
import Testing

@testable import NavigatorKit

@Suite("Snapshot restoration")
@MainActor
struct SnapshotRestorationTests {
    private var registry: RouteTypeRegistry {
        var registry = RouteTypeRegistry()
        registry.register(ProductRoute.self)
        registry.register(ReviewRoute.self)
        registry.register(SettingsRoute.self)
        return registry
    }

    private func makePopulatedScene() -> SceneNavigator {
        let scene = makeTabbedScene()
        guard case .tabs(let tabs) = scene.root else { fatalError() }
        tabs.selection = TabID(AppTab.shop)
        scene.baseContext.path = [AnyRoute(ProductRoute.detail(id: 42))]

        let sheetContent = NavigationContext(
            root: AnyRoute(ReviewRoute.compose(productID: 42)),
            path: [AnyRoute(ProductRoute.detail(id: 1))]
        )
        scene.baseContext.sheet = PresentedContext(style: .sheet(detents: [.medium]), content: sheetContent)
        sheetContent.fullScreenCover = PresentedContext(
            style: .fullScreenCover,
            content: NavigationContext(root: AnyRoute(ProductRoute.detail(id: 2)))
        )

        // Split state in the settings tab.
        if case .split(let split) = tabs.layout(for: TabID(AppTab.settings)) {
            split.sidebarSelection = AnyRoute(SettingsRoute.general)
            split.detailContext.path = [AnyRoute(SettingsRoute.advanced)]
        }

        // Transient state that must NOT persist.
        scene.baseContext.alert = RoutedAlert("Transient")
        return scene
    }

    @Test func roundTripRestoresFullTree() throws {
        let original = makePopulatedScene()
        let data = try NavigationSnapshotCoder.encode(original.snapshot())

        let (snapshot, report) = try #require(NavigationSnapshotCoder.decode(data, routeTypes: registry))
        #expect(report.isClean)

        // Restore into a FRESH blueprint-shaped scene.
        let restored = makeTabbedScene()
        restored.restore(snapshot)

        guard case .tabs(let tabs) = restored.root else { return }
        #expect(tabs.selection == TabID(AppTab.shop))
        #expect(restored.baseContext.path == [AnyRoute(ProductRoute.detail(id: 42))])

        let sheet = try #require(restored.baseContext.sheet)
        #expect(sheet.style == .sheet(detents: [.medium]))
        #expect(sheet.content.root == AnyRoute(ReviewRoute.compose(productID: 42)))
        #expect(sheet.content.path == [AnyRoute(ProductRoute.detail(id: 1))])

        let cover = try #require(sheet.content.fullScreenCover)
        #expect(cover.style == .fullScreenCover)
        #expect(cover.content.root == AnyRoute(ProductRoute.detail(id: 2)))

        if case .split(let split) = tabs.layout(for: TabID(AppTab.settings)) {
            #expect(split.sidebarSelection == AnyRoute(SettingsRoute.general))
            #expect(split.detailContext.path == [AnyRoute(SettingsRoute.advanced)])
        } else {
            Issue.record("Expected settings split")
        }

        // Alerts are transient.
        #expect(restored.baseContext.alert == nil)

        // Round-trip equality of snapshots.
        #expect(restored.snapshot() == snapshot)
    }

    @Test func unknownRouteTypeTruncatesPathAndDropsPresentations() throws {
        let original = makePopulatedScene()
        let data = try NavigationSnapshotCoder.encode(original.snapshot())

        // Decode with a registry missing ProductRoute (e.g. renamed type).
        var partial = RouteTypeRegistry()
        partial.register(ReviewRoute.self)
        partial.register(SettingsRoute.self)

        let (snapshot, report) = try #require(NavigationSnapshotCoder.decode(data, routeTypes: partial))
        #expect(!report.isClean)
        #expect(report.droppedRouteTypeIDs.contains("ProductRoute"))

        let restored = makeTabbedScene()
        restored.restore(snapshot)

        // Shop tab: path element undecodable → truncated to root, sheet dropped.
        #expect(restored.baseContext.path.isEmpty)
        #expect(restored.baseContext.sheet == nil)

        // Settings split survives (SettingsRoute still registered).
        guard case .tabs(let tabs) = restored.root,
            case .split(let split) = tabs.layout(for: TabID(AppTab.settings))
        else {
            Issue.record("Expected settings split")
            return
        }
        #expect(split.detailContext.path == [AnyRoute(SettingsRoute.advanced)])
    }

    @Test func undecodableLayerRootDropsLayerAndAbove() throws {
        let scene = makeTabbedScene()
        // Sheet rooted in ProductRoute with a nested cover above it.
        let sheetContent = NavigationContext(root: AnyRoute(ProductRoute.detail(id: 3)))
        scene.baseContext.sheet = PresentedContext(style: .sheet(), content: sheetContent)
        sheetContent.sheet = PresentedContext(
            style: .sheet(),
            content: NavigationContext(root: AnyRoute(ReviewRoute.compose(productID: 3)))
        )
        let data = try NavigationSnapshotCoder.encode(scene.snapshot())

        var partial = RouteTypeRegistry()
        partial.register(ReviewRoute.self)
        partial.register(SettingsRoute.self)

        let (snapshot, report) = try #require(NavigationSnapshotCoder.decode(data, routeTypes: partial))
        #expect(!report.isClean)

        let restored = makeTabbedScene()
        restored.restore(snapshot)
        // First layer's root undecodable → whole chain gone, even though the
        // second layer's ReviewRoute was decodable.
        #expect(restored.baseContext.sheet == nil)
    }

    @Test func versionMismatchDiscardsSnapshot() throws {
        let scene = makeTabbedScene()
        var snapshot = scene.snapshot()
        snapshot.version = 999
        let data = try NavigationSnapshotCoder.encode(snapshot)
        #expect(NavigationSnapshotCoder.decode(data, routeTypes: registry) == nil)
    }

    @Test func corruptDataDiscarded() {
        #expect(NavigationSnapshotCoder.decode(Data("junk".utf8), routeTypes: registry) == nil)
    }

    @Test func blueprintShapeMismatchSkipsSubtree() throws {
        // Snapshot from a tabbed scene, restored into a stack-only scene.
        let tabbed = makePopulatedScene()
        let data = try NavigationSnapshotCoder.encode(tabbed.snapshot())
        let (snapshot, _) = try #require(NavigationSnapshotCoder.decode(data, routeTypes: registry))

        let stackScene = SceneNavigator(root: .stack(NavigationContext()))
        stackScene.restore(snapshot)  // must not crash
        #expect(stackScene.baseContext.path.isEmpty)
    }

    @Test func rootPresentationChainRoundTrips() throws {
        let scene = makeTabbedScene()
        scene.rootPresentation = PresentedContext(
            style: .fullScreenCover,
            content: NavigationContext(root: AnyRoute(SettingsRoute.menu))
        )
        let data = try NavigationSnapshotCoder.encode(scene.snapshot())
        let (snapshot, _) = try #require(NavigationSnapshotCoder.decode(data, routeTypes: registry))

        let restored = makeTabbedScene()
        restored.restore(snapshot)
        let rootPresentation = try #require(restored.rootPresentation)
        #expect(rootPresentation.style == .fullScreenCover)
        #expect(rootPresentation.content.root == AnyRoute(SettingsRoute.menu))
    }
}
