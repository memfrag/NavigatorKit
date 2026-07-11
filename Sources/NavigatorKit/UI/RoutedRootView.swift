import SwiftUI

/// Renders a ``RootLayout``: stack, tabs, or split.
public struct RoutedRootView: View {
    let layout: RootLayout

    public init(layout: RootLayout) {
        self.layout = layout
    }

    public var body: some View {
        switch layout {
        case .stack(let context):
            RoutedStack(context: context)
        case .tabs(let tabs):
            RoutedTabRoot(tabs: tabs)
        case .split(let split):
            RoutedSplitRoot(split: split)
        }
    }
}

/// A `TabView` bound to a ``TabsLayout``.
public struct RoutedTabRoot: View {
    @Bindable var tabs: TabsLayout

    public init(tabs: TabsLayout) {
        self.tabs = tabs
    }

    public var body: some View {
        TabView(selection: $tabs.selection) {
            ForEach(tabs.tabs) { descriptor in
                Tab(value: descriptor.id, role: descriptor.role?.swiftUIRole) {
                    RoutedRootView(layout: descriptor.content)
                } label: {
                    if let systemImage = descriptor.systemImage {
                        Label(descriptor.title, systemImage: systemImage)
                    } else {
                        Text(descriptor.title)
                    }
                }
            }
        }
    }
}

extension TabDescriptor.TabRole {
    var swiftUIRole: TabRole {
        switch self {
        case .search: .search
        }
    }
}

/// A `NavigationSplitView` bound to a ``SplitLayout``. The sidebar view is
/// resolved from ``SplitLayout/sidebarRoot`` and receives the selection
/// binding via `\.sidebarSelection`; the detail column shows the view for
/// the current sidebar selection at its stack root.
public struct RoutedSplitRoot: View {
    @Bindable var split: SplitLayout

    @Environment(\.destinationRegistry) private var registry

    public init(split: SplitLayout) {
        self.split = split
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: visibilityBinding) {
            Group {
                if let sidebarRoot = split.sidebarRoot {
                    registry.view(for: sidebarRoot)
                } else {
                    UnregisteredRouteView(typeID: "<no sidebar root>")
                }
            }
            .environment(\.sidebarSelection, $split.sidebarSelection)
        } detail: {
            RoutedStack(context: split.detailContext) {
                if let selection = split.sidebarSelection {
                    registry.view(for: selection)
                } else {
                    ContentUnavailableView(
                        "Nothing Selected",
                        systemImage: "sidebar.left",
                        description: Text("Select an item from the sidebar.")
                    )
                }
            }
        }
    }

    private var visibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { split.columnVisibility.swiftUIVisibility },
            set: { split.columnVisibility = SplitColumnVisibility($0) }
        )
    }
}

extension SplitColumnVisibility {
    var swiftUIVisibility: NavigationSplitViewVisibility {
        switch self {
        case .automatic: .automatic
        case .all: .all
        case .doubleColumn: .doubleColumn
        case .detailOnly: .detailOnly
        }
    }

    init(_ visibility: NavigationSplitViewVisibility) {
        switch visibility {
        case .all: self = .all
        case .doubleColumn: self = .doubleColumn
        case .detailOnly: self = .detailOnly
        default: self = .automatic
        }
    }
}

extension EnvironmentValues {
    /// The sidebar selection binding of the enclosing routed split view —
    /// bind it to `List(selection:)` in your sidebar view and tag rows with
    /// `AnyRoute` values.
    @Entry public var sidebarSelection: Binding<AnyRoute?>? = nil
}
