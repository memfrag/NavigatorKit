import NavigatorKit
import ProductsFeature
import ReviewsFeature
import ReviewsInterface
import SearchFeature
import SettingsFeature
import SwiftUI

enum AppTab: String {
    case shop, search, settings, playground
}

// MARK: - Composition

enum ShopComposition {
    /// The only place in the app that knows every feature.
    @MainActor
    static func makeAppNavigator() -> AppNavigator {
        AppNavigator(
            destinations: DestinationRegistry {
                ProductsFeature.destinations
                ReviewsFeature.destinations
                SettingsFeature.destinations
                SearchFeature.destinations
                PlaygroundFeature.destinations
            },
            deepLinks: deepLinks,
            scenePolicy: ReuseSceneShowingRoutePolicy(fallback: .useActive),
            defaultWindowID: "main"
        )
    }

    static let blueprint = SceneBlueprint {
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
            RoutedTab(AppTab.playground, "Playground", systemImage: "wand.and.stars") {
                StackRoot(PlaygroundRoute.home)
            }
            RoutedTab(AppTab.search, "Search", systemImage: "magnifyingglass", role: .search) {
                StackRoot(SearchRoute.home)
            }
        }
    }

    /// shopexample://products/42, shopexample://products/42/review,
    /// shopexample://settings/advanced — plus the same paths as universal
    /// links (https://shop.example.com/...).
    static let deepLinks = DeepLinkMap {
        URLPattern("/products/:id") { params in
            try NavigationIntent {
                SelectTab(AppTab.shop)
                SetStack(ProductRoute.list, ProductRoute.detail(id: try params.id(Int.self)))
            }
        }
        URLPattern("/products/:id/review") { params in
            let id = try params.id(Int.self)
            return NavigationIntent {
                SelectTab(AppTab.shop)
                SetStack(ProductRoute.list, ProductRoute.detail(id: id))
                Present(ReviewRoute.compose(productID: id), style: .sheet(detents: [.medium, .large]))
            }
        }
        URLPattern("/settings/**") { _ in
            NavigationIntent { SelectTab(AppTab.settings) }
        }
    }
}

// MARK: - App

@main
struct ShopApp: App {
    @State private var appNavigator = ShopComposition.makeAppNavigator()

    var body: some Scene {
        WindowGroup(id: "main") {
            RoutedSceneRoot(
                app: appNavigator,
                blueprint: ShopComposition.blueprint,
                restorationKey: "shop.navigation"
            )
            .onOpenURL { appNavigator.open($0) }
        }
    }
}
