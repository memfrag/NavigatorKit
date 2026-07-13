extension Navigator {
    /// A headless navigator for SwiftUI previews and tests.
    ///
    /// It's a *real* navigator — real ``IntentExecutor``, ``Planner``, and
    /// dismissal semantics — wired to ``ImmediateTransitionCoordinator`` so it
    /// applies intents synchronously instead of awaiting real presentation
    /// transitions. Nothing is mocked; assert on ``Navigator/scene`` after
    /// driving it.
    ///
    /// ```swift
    /// #Preview {
    ///     let registry = DestinationRegistry { ProductsFeature.destinations }
    ///     ProductDetailView(id: 42)
    ///         .environment(Navigator.testable(
    ///             root: .stack(NavigationContext(root: AnyRoute(ProductRoute.detail(id: 42)))),
    ///             registry: registry))
    ///         .environment(\.destinationRegistry, registry)
    /// }
    /// ```
    public static func testable(
        root: RootLayout,
        registry: DestinationRegistry = DestinationRegistry()
    ) -> Navigator {
        Navigator(
            scene: SceneNavigator(root: root),
            executor: IntentExecutor(transitions: ImmediateTransitionCoordinator()),
            registry: registry
        )
    }

    /// A headless navigator over a single navigation stack — the common case
    /// for previewing or testing one screen.
    ///
    /// ```swift
    /// let navigator = Navigator.testable(stack: ProductRoute.detail(id: 42))
    /// ```
    public static func testable(
        stack root: (any Route)? = nil,
        path: [any Route] = [],
        registry: DestinationRegistry = DestinationRegistry()
    ) -> Navigator {
        testable(
            root: .stack(
                NavigationContext(
                    root: root.map { AnyRoute($0) },
                    path: path.map { AnyRoute($0) }
                )
            ),
            registry: registry
        )
    }
}
