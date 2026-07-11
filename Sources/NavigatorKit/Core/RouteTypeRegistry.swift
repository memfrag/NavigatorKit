import Foundation

/// Maps stable route type identifiers to decoding functions, enabling
/// ``AnyRoute`` to round-trip through `Codable` despite holding heterogeneous
/// route types from independent modules.
///
/// Apps rarely construct this directly: registering a feature's destinations
/// with ``DestinationRegistry`` also registers its route types here.
public struct RouteTypeRegistry: Sendable {
    private var decoders: [String: @Sendable (any Decoder) throws -> any Route] = [:]

    public init() {}

    /// Registers a route type for decoding under its ``Route/routeTypeID``.
    public mutating func register<R: Route>(_ type: R.Type) {
        decoders[R.routeTypeID] = { try R(from: $0) }
    }

    /// Whether a decoder is registered for the given type identifier.
    public func contains(_ typeID: String) -> Bool {
        decoders[typeID] != nil
    }

    /// All registered type identifiers.
    public var registeredTypeIDs: [String] {
        Array(decoders.keys)
    }

    func decodeRoute(typeID: String, from decoder: any Decoder) throws -> any Route {
        guard let decode = decoders[typeID] else {
            throw RouteCodingError.unknownRouteType(typeID)
        }
        return try decode(decoder)
    }
}

extension RouteTypeRegistry {
    /// A `JSONDecoder` pre-configured with this registry, ready to decode
    /// ``AnyRoute`` (and any type containing it).
    public func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.routeTypeRegistry] = self
        return decoder
    }
}
