import NavigatorKit
import ProductsFeature
import ReviewsInterface
import SettingsFeature
import SwiftUI

enum PlaygroundRoute: Route {
    case home
}

struct PlaygroundFeature: RoutableFeature {
    static var destinations: DestinationGroup {
        Destination(for: PlaygroundRoute.self) { _ in
            PlaygroundView()
        }
    }
}

/// Buttons that exercise the hard parts: compound intents across containers,
/// staged nested presentation, activate-existing, and deep links.
struct PlaygroundView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AppNavigator.self) private var app: AppNavigator?

    var body: some View {
        List {
            Section("The canonical hard intent") {
                Button("Tab → Stack ×2 → Sheet → Push in Sheet → Alert") {
                    navigator.perform(
                        NavigationIntent {
                            SelectTab(AppTab.shop)
                            SetStack(ProductRoute.list, ProductRoute.detail(id: 42))
                            Present(
                                ReviewRoute.compose(productID: 42),
                                style: .sheet(detents: [.medium, .large])
                            )
                            Push(ReviewRoute.photoPicker)
                            Alert("Arrived!", message: "One intent, five containers.")
                        }
                    )
                }
            }

            Section("Dismissal & activation") {
                Button("Activate Product #42 (reveal existing or push)") {
                    navigator.navigate(
                        to: ProductRoute.detail(id: 42),
                        placement: .activateExisting(else: .push)
                    )
                }
                Button("Dismiss Everything") {
                    navigator.dismissAll()
                }
            }

            Section("Split view targeting") {
                Button("Settings → Advanced (sidebar + detail)") {
                    navigator.perform(
                        NavigationIntent {
                            SelectTab(AppTab.settings)
                            SelectSidebar(SettingsRoute.advanced)
                        }
                    )
                }
            }

            Section("Deep links") {
                Button("shopexample://products/42/review") {
                    app?.open(URL(string: "shopexample://products/42/review")!)
                }
                Button("shopexample://settings/anything/deep") {
                    app?.open(URL(string: "shopexample://settings/anything/deep")!)
                }
            }
        }
        .navigationTitle("Playground")
    }
}
