/// Turns a ``NavigationIntent`` into an ``ExecutionPlan`` by simulating the
/// intent's cursor walk against the scene's current tree.
///
/// Pure in effect: planning never mutates live tree state. (Contexts created
/// for `present` operations are configured at plan time, but they are fresh
/// objects that only enter the tree when their present stage applies.)
@MainActor
enum Planner {
    static func plan(_ intent: NavigationIntent, in scene: SceneNavigator) throws -> ExecutionPlan {
        var builder = PlanBuilder(scene: scene)
        for operation in intent.operations {
            try builder.apply(operation)
        }
        return builder.finish()
    }
}

@MainActor
private struct PlanBuilder {
    let scene: SceneNavigator

    private var stages: [ExecutionStage] = []
    private var baseMutations: [PlannedMutation] = []

    /// The context subsequent path/present operations target.
    private var cursor: NavigationContext
    /// True while the cursor is a context created by an earlier `present`
    /// operation in this same intent — not yet attached to the tree, so path
    /// mutations fold directly into it instead of becoming staged mutations.
    private var cursorIsPending = false
    /// The cursor's stack path as it will be after the mutations planned so
    /// far.
    private var simulatedPath: [AnyRoute]

    /// Simulated root-tab selection (live value until a selectTab op).
    private var simulatedTabSelection: TabID?
    /// The base context of the tab/layout that will be visible after the
    /// mutations planned so far.
    private var simulatedVisibleBase: NavigationContext
    /// The layout containing the cursor's base context.
    private var currentLayout: RootLayout

    /// Contexts whose presentations we have already planned to clear.
    private var clearedPresentations: Set<ContextID> = []
    private var clearedRootPresentation = false
    /// Whether any present stage has been emitted (restricts dismiss ops).
    private var hasPendingPresent = false

    init(scene: SceneNavigator) {
        self.scene = scene
        self.cursor = scene.activeContext
        self.simulatedPath = scene.activeContext.path
        self.simulatedVisibleBase = scene.baseContext
        self.currentLayout = scene.root
        if case .tabs(let tabs) = scene.root {
            self.simulatedTabSelection = tabs.selection
            self.currentLayout = tabs.selectedLayout
        }
    }

    // MARK: - Operation dispatch

    mutating func apply(_ operation: NavigationOperation) throws {
        switch operation {
        case .selectTab(let id):
            try applySelectTab(id)
        case .selectSidebar(let selection):
            try applySelectSidebar(selection)
        case .setPath(let path):
            mutatePath(to: path)
        case .push(let route):
            mutatePath(to: simulatedPath + [route])
        case .pop:
            if !simulatedPath.isEmpty {
                mutatePath(to: Array(simulatedPath.dropLast()))
            }
        case .popToRoot:
            mutatePath(to: [])
        case .popTo(let route):
            guard let index = simulatedPath.lastIndex(of: route) else {
                throw NavigationError.routeNotInPath(route)
            }
            mutatePath(to: Array(simulatedPath.prefix(through: index)))
        case .present(let route, let style):
            applyPresent(route, style: style)
        case .dismiss:
            try applyDismiss()
        case .dismissAll:
            try applyDismissAll()
        case .alert(let alert):
            flushBase()
            stages.append(
                ExecutionStage(kind: .overlay, settling: .none, mutations: [.setAlert(cursor, alert)])
            )
        case .confirmationDialog(let dialog):
            flushBase()
            stages.append(
                ExecutionStage(kind: .overlay, settling: .none, mutations: [.setDialog(cursor, dialog)])
            )
        case .activate(let route, let fallback):
            try applyActivate(route, fallback: fallback)
        }
    }

    consuming func finish() -> ExecutionPlan {
        flushBase()
        return ExecutionPlan(stages: stages)
    }

    // MARK: - Tab / sidebar selection

    private mutating func applySelectTab(_ id: TabID) throws {
        guard case .tabs(let tabs) = scene.root else {
            throw NavigationError.noTabsLayout
        }
        guard let layout = tabs.layout(for: id) else {
            throw NavigationError.unknownTab(id)
        }
        if simulatedTabSelection != id {
            // Presentations are visually window-global: anything presented on
            // the outgoing lineage would cover the incoming tab.
            dismissVisibleLineagePresentations()
        }
        baseMutations.append(.selectTab(tabs, id))
        simulatedTabSelection = id
        currentLayout = layout
        retargetCursor(to: layout.primaryContext)
        simulatedVisibleBase = layout.primaryContext
    }

    private mutating func applySelectSidebar(_ selection: AnyRoute?) throws {
        guard let split = Self.findSplit(in: currentLayout) else {
            throw NavigationError.noSplitLayout
        }
        if split.sidebarSelection != selection {
            // The detail column's content changes; a sheet presented from the
            // old detail would linger over the new one.
            clearPresented(of: split.detailContext)
        }
        baseMutations.append(.selectSidebar(split, selection))
        retargetCursor(to: split.detailContext)
    }

    private static func findSplit(in layout: RootLayout) -> SplitLayout? {
        switch layout {
        case .split(let split): split
        case .tabs(let tabs): findSplit(in: tabs.selectedLayout)
        case .stack: nil
        }
    }

    // MARK: - Path mutations

    private mutating func mutatePath(to newPath: [AnyRoute]) {
        if cursorIsPending {
            cursor.path = newPath
        } else {
            // Mutating a stack that has something presented over it: tear the
            // presentation down first, or the change happens invisibly behind
            // it.
            clearPresentationsAbove(cursor)
            baseMutations.append(.setPath(cursor, newPath))
        }
        simulatedPath = newPath
    }

    // MARK: - Present / dismiss

    private mutating func applyPresent(_ route: AnyRoute, style: PresentationStyle) {
        flushBase()
        if !cursorIsPending {
            clearPresentationsAbove(cursor)
        }
        // Fully form the child before attaching: root and any path set by
        // subsequent operations render in the same transaction as the
        // presentation itself. Only *nested* presentations need extra stages.
        let content = NavigationContext(root: route)
        let presented = PresentedContext(style: style, content: content)
        let mutation: PlannedMutation =
            style.isFullScreenCover ? .setCover(cursor, presented) : .setSheet(cursor, presented)
        stages.append(
            ExecutionStage(kind: .present, settling: .appearance(content), mutations: [mutation])
        )
        cursor = content
        cursorIsPending = true
        simulatedPath = []
        hasPendingPresent = true
    }

    private mutating func applyDismiss() throws {
        guard !hasPendingPresent else {
            throw NavigationError.invalidOperation(
                "dismiss cannot follow present within a single intent"
            )
        }
        flushBase()

        if let rootPresentation = scene.rootPresentation, !clearedRootPresentation {
            let chain = rootPresentation.content.selfAndPresentedDescendants
            if let presenter = chain.last(where: { $0.presented != nil }) {
                dismissStage(clearing: presenter)
                retargetCursor(to: presenter)
            } else {
                stages.append(
                    ExecutionStage(
                        kind: .dismiss,
                        settling: .disappearance(rootPresentation.content),
                        mutations: [.setRootPresentation(scene, nil)]
                    )
                )
                clearedRootPresentation = true
                retargetCursor(to: simulatedVisibleBase)
            }
            return
        }

        let chain = simulatedVisibleBase.selfAndPresentedDescendants
        if let presenter = chain.last(where: { $0.presented != nil && !clearedPresentations.contains($0.id) }) {
            dismissStage(clearing: presenter)
            retargetCursor(to: presenter)
        }
        // Nothing presented: no-op.
    }

    private mutating func applyDismissAll() throws {
        guard !hasPendingPresent else {
            throw NavigationError.invalidOperation(
                "dismissAll cannot follow present within a single intent"
            )
        }
        flushBase()
        dismissVisibleLineagePresentations()
        retargetCursor(to: simulatedVisibleBase)
    }

    // MARK: - Activate

    private mutating func applyActivate(_ route: AnyRoute, fallback: ActivationFallback) throws {
        guard !hasPendingPresent else {
            throw NavigationError.invalidOperation(
                "activate cannot follow present within a single intent"
            )
        }

        guard let location = scene.findRoute(where: { $0 == route }) else {
            switch fallback {
            case .push:
                mutatePath(to: simulatedPath + [route])
            case .replaceStack:
                mutatePath(to: [route])
            case .present(let style):
                applyPresent(route, style: style)
            }
            return
        }

        switch location {
        case .inSidebar(let split, let slot):
            if let owner = owningTab(of: split.detailContext) {
                try applySelectTab(owner)
            }
            if slot == .root, split.sidebarSelection != route {
                // The route is the sidebar itself; nothing to select.
            }
            retargetCursor(to: split.detailContext)

        case .inContext(let context, let position):
            if let owner = owningTab(of: context) {
                try applySelectTab(owner)
            } else if !isInsideRootPresentation(context) {
                // Target lives in the base tree; a root presentation covers it.
                dismissRootPresentationIfNeeded()
            }
            clearPresentationsAbove(context)
            retargetCursor(to: context)
            switch position {
            case .root:
                if !simulatedPath.isEmpty {
                    baseMutations.append(.setPath(context, []))
                    simulatedPath = []
                }
            case .path(let index):
                let target = Array(context.path.prefix(through: index))
                if simulatedPath != target {
                    baseMutations.append(.setPath(context, target))
                    simulatedPath = target
                }
            }
        }
    }

    /// The root-level tab whose subtree contains the given context, or `nil`
    /// when the root is not tabbed or the context is outside every tab
    /// (e.g. inside a root presentation).
    private func owningTab(of context: NavigationContext) -> TabID? {
        guard case .tabs(let tabs) = scene.root else { return nil }
        return tabs.tabs.first { descriptor in
            descriptor.content.allContexts.contains { $0 === context }
        }?.id
    }

    private func isInsideRootPresentation(_ context: NavigationContext) -> Bool {
        guard let rootPresentation = scene.rootPresentation else { return false }
        return rootPresentation.content.selfAndPresentedDescendants.contains { $0 === context }
    }

    // MARK: - Dismissal helpers

    /// Emits a dismiss stage for everything presented on the currently
    /// visible lineage: the root presentation plus the visible base context's
    /// presented chain.
    private mutating func dismissVisibleLineagePresentations() {
        dismissRootPresentationIfNeeded()
        clearPresented(of: simulatedVisibleBase)
    }

    private mutating func dismissRootPresentationIfNeeded() {
        guard let rootPresentation = scene.rootPresentation, !clearedRootPresentation else { return }
        stages.append(
            ExecutionStage(
                kind: .dismiss,
                settling: .disappearance(rootPresentation.content),
                mutations: [.setRootPresentation(scene, nil)]
            )
        )
        clearedRootPresentation = true
    }

    /// Emits a dismiss stage clearing whatever covers `context`: its own
    /// presented chain (the outermost removal tears down the rest), plus the
    /// root presentation when `context` is not inside it.
    private mutating func clearPresentationsAbove(_ context: NavigationContext) {
        if !isInsideRootPresentation(context) {
            dismissRootPresentationIfNeeded()
        }
        clearPresented(of: context)
    }

    private mutating func clearPresented(of context: NavigationContext) {
        guard context.presented != nil, !clearedPresentations.contains(context.id) else { return }
        dismissStage(clearing: context)
    }

    private mutating func dismissStage(clearing presenter: NavigationContext) {
        var mutations: [PlannedMutation] = []
        var settling = ExecutionStage.Settling.none
        if let sheet = presenter.sheet {
            mutations.append(.setSheet(presenter, nil))
            settling = .disappearance(sheet.content)
        }
        if let cover = presenter.fullScreenCover {
            mutations.append(.setCover(presenter, nil))
            if case .none = settling {
                settling = .disappearance(cover.content)
            }
        }
        guard !mutations.isEmpty else { return }
        stages.append(ExecutionStage(kind: .dismiss, settling: settling, mutations: mutations))
        clearedPresentations.insert(presenter.id)
    }

    // MARK: - Cursor / stage bookkeeping

    private mutating func retargetCursor(to context: NavigationContext) {
        cursor = context
        cursorIsPending = false
        simulatedPath = context.path
    }

    private mutating func flushBase() {
        guard !baseMutations.isEmpty else { return }
        stages.append(ExecutionStage(kind: .base, settling: .none, mutations: baseMutations))
        baseMutations = []
    }
}
