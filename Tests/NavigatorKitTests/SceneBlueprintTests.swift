import Testing

@testable import NavigatorKit

@Suite("SceneBlueprint")
@MainActor
struct SceneBlueprintTests {
    static let main = SceneBlueprint {
        TabsRoot(initialSelection: AppTab.shop) {
            RoutedTab(AppTab.shop, "Shop", systemImage: "bag") {
                StackRoot(ProductRoute.list)
            }
            RoutedTab(AppTab.settings, "Settings", systemImage: "gear") {
                SplitRoot(
                    sidebar: SettingsRoute.menu,
                    initialSidebarSelection: SettingsRoute.general
                )
            }
            RoutedTab(AppTab.search, "Search", systemImage: "magnifyingglass", role: .search) {
                StackRoot()
            }
        }
    }

    @Test func instantiatesDeclaredShape() {
        let scene = Self.main.makeSceneNavigator()

        guard case .tabs(let tabs) = scene.root else {
            Issue.record("Expected tabs root")
            return
        }
        #expect(tabs.selection == TabID(AppTab.shop))
        #expect(tabs.tabs.map(\.id) == [TabID(AppTab.shop), TabID(AppTab.settings), TabID(AppTab.search)])
        #expect(tabs.tabs[2].role == .search)

        #expect(scene.baseContext.root == AnyRoute(ProductRoute.list))
        #expect(scene.baseContext.path.isEmpty)

        guard case .split(let split) = tabs.layout(for: TabID(AppTab.settings)) else {
            Issue.record("Expected split in settings tab")
            return
        }
        #expect(split.sidebarRoot == AnyRoute(SettingsRoute.menu))
        #expect(split.sidebarSelection == AnyRoute(SettingsRoute.general))
        #expect(split.detailContext.path.isEmpty)
    }

    @Test func eachInstantiationIsIndependent() {
        let first = Self.main.makeSceneNavigator()
        let second = Self.main.makeSceneNavigator()
        first.baseContext.path = [AnyRoute(ProductRoute.detail(id: 1))]
        #expect(second.baseContext.path.isEmpty)
        #expect(first.id != second.id)
    }

    @Test func stackRootWithInitialPath() {
        let blueprint = SceneBlueprint {
            StackRoot(ProductRoute.list, path: [ProductRoute.detail(id: 7)])
        }
        let scene = blueprint.makeSceneNavigator()
        #expect(scene.baseContext.path == [AnyRoute(ProductRoute.detail(id: 7))])
    }
}
