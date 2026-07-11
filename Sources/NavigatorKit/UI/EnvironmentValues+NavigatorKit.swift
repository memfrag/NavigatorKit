import SwiftUI

extension EnvironmentValues {
    /// The destination registry used to resolve route views. Installed at
    /// the scene root by `RoutedSceneRoot` (or manually via
    /// `.environment(\.destinationRegistry, registry)`).
    @Entry public var destinationRegistry = DestinationRegistry()

    /// The navigation context enclosing this view — the stack it is pushed
    /// on (or presented in). `nil` outside any routed container.
    @Entry public var navigationContext: NavigationContext? = nil
}
