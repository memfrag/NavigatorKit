import Foundation

/// Serialization entry points for ``NavigationSnapshot``.
public enum NavigationSnapshotCoder {
    /// Encodes a snapshot (no registry needed).
    public static func encode(_ snapshot: NavigationSnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    /// Decodes leniently against the given route registry. Returns `nil`
    /// when the data is unreadable or from a different format version;
    /// otherwise the snapshot plus a report of anything dropped.
    public static func decode(
        _ data: Data,
        routeTypes: RouteTypeRegistry
    ) -> (snapshot: NavigationSnapshot, report: RestorationReport)? {
        let collector = RestorationIssueCollector()
        let decoder = JSONDecoder()
        decoder.userInfo[.routeTypeRegistry] = routeTypes
        decoder.userInfo[.restorationIssues] = collector

        guard let snapshot = try? decoder.decode(NavigationSnapshot.self, from: data),
            snapshot.version == NavigationSnapshot.currentVersion
        else {
            return nil
        }
        return (snapshot, RestorationReport(droppedRouteTypeIDs: collector.droppedRouteTypeIDs))
    }
}

// MARK: - Capture

extension SceneNavigator {
    /// Captures the scene's current navigation state as a persistable value
    /// tree. Alerts/dialogs are excluded by design.
    public func snapshot() -> NavigationSnapshot {
        NavigationSnapshot(
            root: Self.snapshot(of: root),
            rootPresentedChain: Self.presentedChain(startingAt: rootPresentation)
        )
    }

    private static func snapshot(of layout: RootLayout) -> RootSnapshot {
        switch layout {
        case .stack(let context):
            .stack(snapshot(of: context))
        case .tabs(let tabs):
            .tabs(
                TabsSnapshot(
                    selection: tabs.selection,
                    tabs: tabs.tabs.map { TabsSnapshot.Entry(id: $0.id, content: snapshot(of: $0.content)) }
                )
            )
        case .split(let split):
            .split(
                SplitSnapshot(
                    columnVisibility: split.columnVisibility,
                    sidebarSelection: split.sidebarSelection,
                    detail: snapshot(of: split.detailContext)
                )
            )
        }
    }

    private static func snapshot(of context: NavigationContext) -> ContextSnapshot {
        ContextSnapshot(
            root: context.root,
            path: context.path,
            presentedChain: presentedChain(startingAt: context.presented)
        )
    }

    private static func presentedChain(startingAt first: PresentedContext?) -> [PresentedLayerSnapshot] {
        var chain: [PresentedLayerSnapshot] = []
        var current = first
        while let presented = current {
            chain.append(
                PresentedLayerSnapshot(
                    style: presented.style,
                    root: presented.content.root,
                    path: presented.content.path
                )
            )
            current = presented.content.presented
        }
        return chain
    }
}

// MARK: - Restore

extension SceneNavigator {
    /// Applies a snapshot to this scene's (blueprint-instantiated) tree in
    /// one shot: selections, paths, and presentation chains. Subtrees whose
    /// shape no longer matches the blueprint are skipped.
    public func restore(_ snapshot: NavigationSnapshot) {
        Self.apply(snapshot.root, to: root)
        rootPresentation = Self.buildChain(snapshot.rootPresentedChain)
    }

    private static func apply(_ snapshot: RootSnapshot, to layout: RootLayout) {
        switch (snapshot, layout) {
        case (.stack(let contextSnapshot), .stack(let context)):
            apply(contextSnapshot, to: context)

        case (.tabs(let tabsSnapshot), .tabs(let tabs)):
            if tabs.tabs.contains(where: { $0.id == tabsSnapshot.selection }) {
                tabs.selection = tabsSnapshot.selection
            }
            for entry in tabsSnapshot.tabs {
                if let tabLayout = tabs.layout(for: entry.id) {
                    apply(entry.content, to: tabLayout)
                }
            }

        case (.split(let splitSnapshot), .split(let split)):
            split.columnVisibility = splitSnapshot.columnVisibility
            split.sidebarSelection = splitSnapshot.sidebarSelection
            apply(splitSnapshot.detail, to: split.detailContext)

        default:
            // Blueprint shape changed since the snapshot: skip this subtree.
            break
        }
    }

    private static func apply(_ snapshot: ContextSnapshot, to context: NavigationContext) {
        context.path = snapshot.path
        context.alert = nil
        context.confirmationDialog = nil
        let chain = buildChain(snapshot.presentedChain)
        if chain?.style.isFullScreenCover == true {
            context.sheet = nil
            context.fullScreenCover = chain
        } else {
            context.sheet = chain
            context.fullScreenCover = nil
        }
    }

    private static func buildChain(_ layers: [PresentedLayerSnapshot]) -> PresentedContext? {
        guard let first = layers.first else { return nil }
        let content = NavigationContext(root: first.root, path: first.path)
        let inner = buildChain(Array(layers.dropFirst()))
        if inner?.style.isFullScreenCover == true {
            content.fullScreenCover = inner
        } else {
            content.sheet = inner
        }
        return PresentedContext(style: first.style, content: content)
    }
}
