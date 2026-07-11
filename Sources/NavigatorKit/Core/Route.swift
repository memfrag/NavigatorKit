/// A navigation destination value.
///
/// Feature modules conform their route enums or structs to `Route`. Routes are
/// pure values — they carry the data needed to construct a destination view,
/// but know nothing about views themselves. The mapping from a route to a view
/// is declared separately via ``Destination`` registration.
///
/// ```swift
/// public enum ProductRoute: Route {
///     case list
///     case detail(id: Int)
/// }
/// ```
public protocol Route: Hashable, Codable, Sendable {
    /// Stable identifier used for `Codable` round-tripping and registry lookup.
    ///
    /// Defaults to the unqualified type name. Override it to keep persisted
    /// navigation state restorable across type renames.
    static var routeTypeID: String { get }
}

extension Route {
    public static var routeTypeID: String { String(describing: Self.self) }
}
