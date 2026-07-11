import NavigatorKit
import ReviewsInterface
import SwiftUI

public enum ProductRoute: Route {
    case list
    case detail(id: Int)
}

public struct ProductsFeature: RoutableFeature {
    public static var destinations: DestinationGroup {
        Destination(for: ProductRoute.self) { route in
            switch route {
            case .list:
                ProductListView()
            case .detail(let id):
                ProductDetailView(id: id)
            }
        }
    }
}

// MARK: - Views

struct Product: Identifiable {
    let id: Int
    let name: String

    static let all: [Product] = [
        Product(id: 1, name: "Aeropress"),
        Product(id: 2, name: "Chemex"),
        Product(id: 3, name: "Hario V60"),
        Product(id: 42, name: "La Marzocco Linea Mini"),
    ]
}

struct ProductListView: View {
    var body: some View {
        List(Product.all) { product in
            // Value-based link: pushes through the routed stack.
            RouteLink(ProductRoute.detail(id: product.id)) {
                LabeledContent(product.name, value: "#\(product.id)")
            }
        }
        .navigationTitle("Shop")
    }
}

struct ProductDetailView: View {
    let id: Int

    @Environment(Navigator.self) private var navigator
    @Environment(AppNavigator.self) private var app: AppNavigator?

    private var product: Product {
        Product.all.first { $0.id == id } ?? Product(id: id, name: "Product #\(id)")
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Product", value: product.name)
                LabeledContent("ID", value: "#\(id)")
            }

            Section("Actions") {
                Button("Write a Review") {
                    // Cross-feature navigation via the interface target; the
                    // placement (sheet) is whatever reviews registered.
                    navigator.navigate(to: ReviewRoute.compose(productID: id))
                }
                Button("Related Product") {
                    navigator.push(ProductRoute.detail(id: id + 1))
                }
                Button("Back to All Products") {
                    navigator.navigate(
                        to: ProductRoute.list,
                        placement: .activateExisting(else: .replaceStack)
                    )
                }
            }

            if let app {
                Section("Windows") {
                    Button("Open in New Window") {
                        app.perform(
                            NavigationIntent {
                                SetStack(ProductRoute.detail(id: id))
                            },
                            scenePreference: .newWindow()
                        )
                    }
                }
            }
        }
        .navigationTitle(product.name)
    }
}
