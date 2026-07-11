import Observation

/// The container shape at (some level of) a scene's root: a single stack,
/// a tab bar, or a split view. Tabs may themselves host splits or stacks,
/// covering the iPad "tab bar + split view" pattern.
public enum RootLayout {
    case stack(NavigationContext)
    case tabs(TabsLayout)
    case split(SplitLayout)
}

extension RootLayout {
    /// The context that base navigation operations target for this layout:
    /// the stack itself, the selected tab's primary context, or the split
    /// view's detail context.
    @MainActor
    public var primaryContext: NavigationContext {
        switch self {
        case .stack(let context): context
        case .tabs(let tabs): tabs.selectedLayout.primaryContext
        case .split(let split): split.detailContext
        }
    }

    /// Every context reachable in this layout, including presented
    /// descendants — used for route search (scene policies, activate-existing).
    @MainActor
    public var allContexts: [NavigationContext] {
        baseContexts.flatMap(\.selfAndPresentedDescendants)
    }

    /// The base (unpresented) contexts of this layout across all tabs/columns.
    @MainActor
    public var baseContexts: [NavigationContext] {
        switch self {
        case .stack(let context):
            [context]
        case .tabs(let tabs):
            tabs.tabs.flatMap { $0.content.baseContexts }
        case .split(let split):
            (split.contentContext.map { [$0] } ?? []) + [split.detailContext]
        }
    }
}

// MARK: - Tabs

/// State of a tab-bar root: which tab is selected and what each tab hosts.
@MainActor
@Observable
public final class TabsLayout {
    public var selection: TabID
    public let tabs: [TabDescriptor]

    public init(selection: TabID, tabs: [TabDescriptor]) {
        precondition(!tabs.isEmpty, "TabsLayout requires at least one tab")
        precondition(
            tabs.contains { $0.id == selection },
            "Initial selection \(selection.rawValue) is not among the declared tabs"
        )
        self.selection = selection
        self.tabs = tabs
    }

    /// The layout hosted by the given tab, if it exists.
    public func layout(for tab: TabID) -> RootLayout? {
        tabs.first { $0.id == tab }?.content
    }

    /// The layout hosted by the selected tab.
    public var selectedLayout: RootLayout {
        guard let layout = layout(for: selection) else {
            preconditionFailure("Selected tab \(selection.rawValue) is not among the declared tabs")
        }
        return layout
    }
}

/// One tab: identity, chrome, and the layout it hosts.
public struct TabDescriptor: Identifiable {
    public let id: TabID
    public let title: String
    public let systemImage: String?
    public let role: TabRole?
    public let content: RootLayout

    public enum TabRole: Sendable {
        /// The system search tab (bottom-trailing placement on iOS 26).
        case search
    }

    public init(
        id: TabID,
        title: String,
        systemImage: String? = nil,
        role: TabRole? = nil,
        content: RootLayout
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.content = content
    }
}

// MARK: - Split

/// A `Codable` mirror of SwiftUI's `NavigationSplitViewVisibility`.
public enum SplitColumnVisibility: String, Sendable, Codable {
    case automatic, all, doubleColumn, detailOnly
}

/// State of a navigation split view.
///
/// The sidebar is a *selection*, not a stack — it binds to
/// `List(selection:)`. The detail column is a full ``NavigationContext``
/// (stack + presentations), so intents address it exactly like a tab's stack.
@MainActor
@Observable
public final class SplitLayout {
    public var columnVisibility: SplitColumnVisibility

    /// The route rendered as the sidebar's content, or `nil` when the
    /// composition layer supplies the sidebar view directly.
    public let sidebarRoot: AnyRoute?

    /// The selected sidebar item; binds to `List(selection:)`.
    public var sidebarSelection: AnyRoute?

    /// Middle column context (three-column splits only).
    public let contentContext: NavigationContext?

    /// The detail column: a full navigation context.
    public let detailContext: NavigationContext

    public init(
        columnVisibility: SplitColumnVisibility = .automatic,
        sidebarRoot: AnyRoute? = nil,
        sidebarSelection: AnyRoute? = nil,
        contentContext: NavigationContext? = nil,
        detailContext: NavigationContext = NavigationContext()
    ) {
        self.columnVisibility = columnVisibility
        self.sidebarRoot = sidebarRoot
        self.sidebarSelection = sidebarSelection
        self.contentContext = contentContext
        self.detailContext = detailContext
    }
}
