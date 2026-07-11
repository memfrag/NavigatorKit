/// Errors thrown while planning or executing a ``NavigationIntent``.
public enum NavigationError: Error, Sendable, Equatable {
    /// A tab operation was used but the scene's root is not a tab layout.
    case noTabsLayout
    /// The selected tab is not among the scene's declared tabs.
    case unknownTab(TabID)
    /// A sidebar operation was used but no split view is in the cursor's
    /// layout.
    case noSplitLayout
    /// `popTo` targeted a route that is not in the cursor context's stack.
    case routeNotInPath(AnyRoute)
    /// The operation sequence is not executable as one intent.
    case invalidOperation(String)
}
