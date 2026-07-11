/// Declares a scene's container shape — tabs, splits, stacks — *as data*,
/// so scene creation, intents, and restoration all understand it. Each new
/// window instantiates a fresh ``SceneNavigator`` tree from the blueprint,
/// which is what makes per-window navigation state automatic.
///
/// ```swift
/// static let main = SceneBlueprint {
///     TabsRoot(initialSelection: AppTab.shop) {
///         RoutedTab(AppTab.shop, "Shop", systemImage: "bag") {
///             StackRoot(ProductRoute.list)
///         }
///         RoutedTab(AppTab.settings, "Settings", systemImage: "gear") {
///             SplitRoot(sidebar: SettingsRoute.menu)
///         }
///     }
/// }
/// ```
///
/// Roots are declared as routes and resolved through the destination
/// registry; for a custom root view, register a dedicated route type for it.
public struct SceneBlueprint: Sendable {
    let root: LayoutBlueprint

    public init(@SceneBlueprintBuilder _ build: () -> LayoutBlueprint) {
        self.root = build()
    }

    /// Instantiates a fresh scene state tree.
    @MainActor
    public func makeSceneNavigator() -> SceneNavigator {
        SceneNavigator(root: root.makeLayout())
    }
}

/// The value form of a ``RootLayout``.
public indirect enum LayoutBlueprint: Sendable {
    case stack(StackRoot)
    case tabs(TabsRoot)
    case split(SplitRoot)

    @MainActor
    func makeLayout() -> RootLayout {
        switch self {
        case .stack(let stack):
            .stack(stack.makeContext())
        case .tabs(let tabs):
            .tabs(tabs.makeLayout())
        case .split(let split):
            .split(split.makeLayout())
        }
    }
}

/// Anything usable as a layout position in a blueprint.
public protocol LayoutBlueprintConvertible {
    var layoutBlueprint: LayoutBlueprint { get }
}

@resultBuilder
public enum SceneBlueprintBuilder {
    public static func buildExpression(_ expression: some LayoutBlueprintConvertible) -> LayoutBlueprint {
        expression.layoutBlueprint
    }

    public static func buildBlock(_ component: LayoutBlueprint) -> LayoutBlueprint {
        component
    }
}

// MARK: - Roots

/// A navigation stack root.
public struct StackRoot: Sendable, LayoutBlueprintConvertible {
    let root: AnyRoute?
    let initialPath: [AnyRoute]

    public init(_ root: (any Route)? = nil, path: [any Route] = []) {
        self.root = root.map { AnyRoute($0) }
        self.initialPath = path.map { AnyRoute($0) }
    }

    public var layoutBlueprint: LayoutBlueprint { .stack(self) }

    @MainActor
    func makeContext() -> NavigationContext {
        NavigationContext(root: root, path: initialPath)
    }
}

/// A tab-bar root.
public struct TabsRoot: Sendable, LayoutBlueprintConvertible {
    let initialSelection: TabID
    let tabs: [RoutedTab]

    public init(initialSelection: TabID, @RoutedTabsBuilder tabs: () -> [RoutedTab]) {
        self.initialSelection = initialSelection
        self.tabs = tabs()
    }

    public init<T: RawRepresentable>(
        initialSelection: T,
        @RoutedTabsBuilder tabs: () -> [RoutedTab]
    ) where T.RawValue == String {
        self.init(initialSelection: TabID(initialSelection), tabs: tabs)
    }

    public var layoutBlueprint: LayoutBlueprint { .tabs(self) }

    @MainActor
    func makeLayout() -> TabsLayout {
        TabsLayout(
            selection: initialSelection,
            tabs: tabs.map { tab in
                TabDescriptor(
                    id: tab.id,
                    title: tab.title,
                    systemImage: tab.systemImage,
                    role: tab.role,
                    content: tab.content.makeLayout()
                )
            }
        )
    }
}

/// One tab declaration in a ``TabsRoot``.
public struct RoutedTab: Sendable {
    let id: TabID
    let title: String
    let systemImage: String?
    let role: TabDescriptor.TabRole?
    let content: LayoutBlueprint

    public init(
        _ id: TabID,
        _ title: String,
        systemImage: String? = nil,
        role: TabDescriptor.TabRole? = nil,
        @SceneBlueprintBuilder content: () -> LayoutBlueprint
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.content = content()
    }

    public init<T: RawRepresentable>(
        _ id: T,
        _ title: String,
        systemImage: String? = nil,
        role: TabDescriptor.TabRole? = nil,
        @SceneBlueprintBuilder content: () -> LayoutBlueprint
    ) where T.RawValue == String {
        self.init(TabID(id), title, systemImage: systemImage, role: role, content: content)
    }
}

@resultBuilder
public enum RoutedTabsBuilder {
    public static func buildExpression(_ expression: RoutedTab) -> [RoutedTab] {
        [expression]
    }

    public static func buildBlock(_ components: [RoutedTab]...) -> [RoutedTab] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [RoutedTab]?) -> [RoutedTab] {
        component ?? []
    }

    public static func buildEither(first component: [RoutedTab]) -> [RoutedTab] {
        component
    }

    public static func buildEither(second component: [RoutedTab]) -> [RoutedTab] {
        component
    }

    public static func buildArray(_ components: [[RoutedTab]]) -> [RoutedTab] {
        components.flatMap(\.self)
    }
}

/// A two-column split-view root: sidebar (selection-driven) plus a detail
/// stack.
public struct SplitRoot: Sendable, LayoutBlueprintConvertible {
    let sidebar: AnyRoute?
    let initialSidebarSelection: AnyRoute?
    let detail: StackRoot
    let columnVisibility: SplitColumnVisibility

    public init(
        sidebar: (any Route)? = nil,
        initialSidebarSelection: (any Route)? = nil,
        detail: StackRoot = StackRoot(),
        columnVisibility: SplitColumnVisibility = .automatic
    ) {
        self.sidebar = sidebar.map { AnyRoute($0) }
        self.initialSidebarSelection = initialSidebarSelection.map { AnyRoute($0) }
        self.detail = detail
        self.columnVisibility = columnVisibility
    }

    public var layoutBlueprint: LayoutBlueprint { .split(self) }

    @MainActor
    func makeLayout() -> SplitLayout {
        SplitLayout(
            columnVisibility: columnVisibility,
            sidebarRoot: sidebar,
            sidebarSelection: initialSidebarSelection,
            detailContext: detail.makeContext()
        )
    }
}
