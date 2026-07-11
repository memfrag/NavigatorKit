import NavigatorKit
import SwiftUI

public enum SearchRoute: Route {
    case home
}

public struct SearchFeature: RoutableFeature {
    public static var destinations: DestinationGroup {
        Destination(for: SearchRoute.self) { route in
            switch route {
            case .home:
                SearchHomeView()
            }
        }
    }
}

struct SearchHomeView: View {
    @State private var query = ""

    var body: some View {
        ContentUnavailableView.search(text: query.isEmpty ? "…" : query)
            .searchable(text: $query)
            .navigationTitle("Search")
    }
}
