/// One declarative navigation step within a ``NavigationIntent``.
///
/// Operations apply to a *cursor* that starts at the scene's active context
/// and moves as operations execute: ``selectTab(_:)`` retargets it to that
/// tab's base context, ``present(_:style:)`` descends into the newly
/// presented child. This makes "tab → stack → sheet → stack in sheet →
/// alert" expressible as a flat, ordered list.
public enum NavigationOperation: Sendable {
    /// Select a tab at the scene's root tab bar. The cursor moves to that
    /// tab's primary context.
    case selectTab(TabID)

    /// Set the sidebar selection of the split view containing the cursor.
    /// The cursor moves to the split's detail context.
    case selectSidebar(AnyRoute?)

    /// Replace the cursor context's stack path.
    case setPath([AnyRoute])

    /// Push a route onto the cursor context's stack.
    case push(AnyRoute)

    /// Pop one route off the cursor context's stack (no-op when empty).
    case pop

    /// Pop the cursor context's stack to its root.
    case popToRoot

    /// Pop to the last occurrence of the given route in the cursor context's
    /// stack. Fails with ``NavigationError/routeNotInPath(_:)`` when absent.
    case popTo(AnyRoute)

    /// Present the route as the root of a new child context over the cursor.
    /// The cursor descends into the child.
    case present(AnyRoute, style: PresentationStyle)

    /// Dismiss the deepest presentation in the scene. The cursor moves to the
    /// presenting context. No-op when nothing is presented.
    case dismiss

    /// Dismiss the root presentation and everything presented on the current
    /// base context. The cursor moves to the base context.
    case dismissAll

    /// Show an alert on the cursor context.
    case alert(RoutedAlert)

    /// Show a confirmation dialog on the cursor context.
    case confirmationDialog(RoutedDialog)

    /// Reveal an existing instance of the route if the scene already shows
    /// one (selecting its tab, dismissing what covers it, popping to it);
    /// otherwise apply the fallback at the current cursor.
    case activate(AnyRoute, fallback: ActivationFallback)
}

/// What ``NavigationOperation/activate(_:fallback:)`` does when the route is
/// not currently in the scene's tree.
public enum ActivationFallback: Sendable {
    case push
    case replaceStack
    case present(PresentationStyle)
}
