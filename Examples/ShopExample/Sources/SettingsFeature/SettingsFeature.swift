import NavigatorKit
import SwiftUI

public enum SettingsRoute: Route {
    case menu
    case general
    case appearance
    case advanced
}

public struct SettingsFeature: RoutableFeature {
    public static var destinations: DestinationGroup {
        Destination(for: SettingsRoute.self) { route in
            switch route {
            case .menu:
                SettingsSidebarView()
            case .general:
                SettingsDetailView(title: "General", pushTarget: .advanced)
            case .appearance:
                SettingsDetailView(title: "Appearance", pushTarget: nil)
            case .advanced:
                SettingsDetailView(title: "Advanced", pushTarget: nil)
            }
        }
    }
}

// MARK: - Views

/// The split view's sidebar: a selection-driven list bound to the routed
/// split via `\.sidebarSelection`.
struct SettingsSidebarView: View {
    @Environment(\.sidebarSelection) private var selection

    var body: some View {
        List(selection: selection ?? .constant(nil)) {
            Label("General", systemImage: "gear")
                .tag(AnyRoute(SettingsRoute.general))
            Label("Appearance", systemImage: "paintbrush")
                .tag(AnyRoute(SettingsRoute.appearance))
            Label("Advanced", systemImage: "wrench.and.screwdriver")
                .tag(AnyRoute(SettingsRoute.advanced))
        }
        .navigationTitle("Settings")
    }
}

struct SettingsDetailView: View {
    let title: String
    let pushTarget: SettingsRoute?

    @Environment(Navigator.self) private var navigator

    var body: some View {
        Form {
            LabeledContent("Section", value: title)
            if let pushTarget {
                Button("Push Deeper") {
                    navigator.push(pushTarget)
                }
            }
        }
        .navigationTitle(title)
    }
}
