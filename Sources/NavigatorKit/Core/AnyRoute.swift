/// A type-erased ``Route``.
///
/// `AnyRoute` lets heterogeneous route types from independent feature modules
/// flow through a single navigation path (`[AnyRoute]` binds directly to
/// `NavigationStack(path:)`). Unlike `NavigationPath`, the contents remain
/// inspectable — which is what makes pop-to-existing-route, scene-matching
/// policies, and intent diffing possible.
public struct AnyRoute: Hashable, Sendable {
    /// The wrapped route value.
    public let base: any Route

    /// The stable type identifier of the wrapped route (``Route/routeTypeID``).
    public let typeID: String

    public init(_ route: some Route) {
        self.base = route
        self.typeID = type(of: route).routeTypeID
    }

    /// Re-boxing an `AnyRoute` is the identity operation.
    public init(_ route: AnyRoute) {
        self = route
    }

    /// Attempts to cast the wrapped route to a concrete type.
    public func `as`<R: Route>(_ type: R.Type) -> R? {
        base as? R
    }

    /// Whether the wrapped route is of the given concrete type.
    public func `is`<R: Route>(_ type: R.Type) -> Bool {
        base is R
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.typeID == rhs.typeID && AnyHashable(lhs.base) == AnyHashable(rhs.base)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeID)
        hasher.combine(AnyHashable(base))
    }
}

extension AnyRoute: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { String(describing: base) }
    public var debugDescription: String { "AnyRoute(\(typeID): \(base))" }
}

// MARK: - Codable

extension AnyRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    /// Encodes as `{ "type": "<routeTypeID>", "value": <route payload> }`.
    /// Encoding needs no registry; decoding requires a ``RouteTypeRegistry``
    /// in the decoder's `userInfo` under ``CodingUserInfoKey/routeTypeRegistry``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeID, forKey: .type)
        try base.encode(to: container.superEncoder(forKey: .value))
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeID = try container.decode(String.self, forKey: .type)
        guard let registry = decoder.userInfo[.routeTypeRegistry] as? RouteTypeRegistry else {
            throw RouteCodingError.missingRegistry
        }
        let route = try registry.decodeRoute(
            typeID: typeID,
            from: container.superDecoder(forKey: .value)
        )
        self.init(route)
    }
}

extension CodingUserInfoKey {
    /// Key under which a ``RouteTypeRegistry`` must be supplied in a decoder's
    /// `userInfo` for ``AnyRoute`` decoding.
    public static let routeTypeRegistry = CodingUserInfoKey(
        rawValue: "NavigatorKit.routeTypeRegistry"
    )!
}

/// Errors thrown while encoding or decoding routes.
public enum RouteCodingError: Error, Sendable, Equatable {
    /// No ``RouteTypeRegistry`` was found in the decoder's `userInfo`.
    case missingRegistry
    /// The persisted `routeTypeID` has no registered decoder — typically a
    /// route type that was renamed or removed, or a feature that was never
    /// registered this launch.
    case unknownRouteType(String)
}
