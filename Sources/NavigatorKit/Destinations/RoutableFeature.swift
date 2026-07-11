/// Conformed to by feature modules to declare their route → view mappings.
///
/// Features know nothing about the app shell or each other; the app's
/// composition layer collects them:
///
/// ```swift
/// // In ProductsFeature:
/// public struct ProductsFeature: RoutableFeature {
///     public static var destinations: DestinationGroup {
///         Destination(for: ProductRoute.self) { route in ... }
///     }
/// }
///
/// // In the app:
/// let registry = DestinationRegistry {
///     ProductsFeature.destinations
///     ReviewsFeature.destinations
/// }
/// ```
public protocol RoutableFeature {
    @DestinationBuilder static var destinations: DestinationGroup { get }
}
