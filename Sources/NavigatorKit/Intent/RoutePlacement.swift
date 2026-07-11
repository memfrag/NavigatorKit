/// Where `navigate(to:)` puts a single route, and what gets dismissed or
/// popped to show it.
///
/// Resolution order when navigating: explicit argument → the route type's
/// default declared at destination registration → `.push`.
public enum RoutePlacement: Sendable {
    /// Push onto the deepest active context (the default).
    case push

    /// Replace the active context's entire stack with just this route.
    case replaceStack

    /// Present over the active context.
    case present(PresentationStyle)

    /// If the scene already shows this route, reveal it (select its tab,
    /// dismiss what covers it, pop to it); otherwise apply the fallback.
    /// Never mutates sibling tabs' stacks.
    case activateExisting(else: ActivationFallback)

    /// Sugar for `.present(.sheet(...))`.
    public static func sheet(
        detents: [PresentationDetentKind] = [],
        showsDragIndicator: Bool = false,
        interactiveDismissDisabled: Bool = false
    ) -> RoutePlacement {
        .present(
            .sheet(
                detents: detents,
                showsDragIndicator: showsDragIndicator,
                interactiveDismissDisabled: interactiveDismissDisabled
            )
        )
    }

    /// Sugar for `.present(.fullScreenCover)`.
    public static var fullScreenCover: RoutePlacement {
        .present(.fullScreenCover)
    }
}
