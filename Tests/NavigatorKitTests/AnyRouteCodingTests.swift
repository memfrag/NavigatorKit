import Foundation
import Testing

@testable import NavigatorKit

// MARK: - Test fixtures

enum ProductRoute: Route {
    case list
    case detail(id: Int)
}

enum ReviewRoute: Route {
    case compose(productID: Int)
}

struct RenamedRoute: Route {
    static var routeTypeID: String { "LegacyRoute" }
    var value: String
}

// MARK: - Hashable

@Suite("AnyRoute Hashable")
struct AnyRouteHashableTests {
    @Test func equalRoutesBoxEqually() {
        #expect(AnyRoute(ProductRoute.detail(id: 42)) == AnyRoute(ProductRoute.detail(id: 42)))
    }

    @Test func differentPayloadsAreUnequal() {
        #expect(AnyRoute(ProductRoute.detail(id: 1)) != AnyRoute(ProductRoute.detail(id: 2)))
    }

    @Test func differentTypesAreUnequal() {
        #expect(AnyRoute(ProductRoute.list) != AnyRoute(ReviewRoute.compose(productID: 1)))
    }

    @Test func hashingIsConsistentWithEquality() {
        let a = AnyRoute(ProductRoute.detail(id: 42))
        let b = AnyRoute(ProductRoute.detail(id: 42))
        #expect(a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
    }

    @Test func reboxingIsIdentity() {
        let boxed = AnyRoute(ProductRoute.list)
        #expect(AnyRoute(boxed) == boxed)
        #expect(AnyRoute(boxed).typeID == "ProductRoute")
    }

    @Test func casting() {
        let route = AnyRoute(ProductRoute.detail(id: 7))
        #expect(route.as(ProductRoute.self) == .detail(id: 7))
        #expect(route.as(ReviewRoute.self) == nil)
        #expect(route.is(ProductRoute.self))
        #expect(!route.is(ReviewRoute.self))
    }
}

// MARK: - Codable

@Suite("AnyRoute Codable")
struct AnyRouteCodingTests {
    private var registry: RouteTypeRegistry {
        var registry = RouteTypeRegistry()
        registry.register(ProductRoute.self)
        registry.register(ReviewRoute.self)
        registry.register(RenamedRoute.self)
        return registry
    }

    @Test func roundTrip() throws {
        let original = AnyRoute(ProductRoute.detail(id: 42))
        let data = try JSONEncoder().encode(original)
        let decoded = try registry.jsonDecoder().decode(AnyRoute.self, from: data)
        #expect(decoded == original)
        #expect(decoded.as(ProductRoute.self) == .detail(id: 42))
    }

    @Test func roundTripArrayOfMixedTypes() throws {
        let original = [
            AnyRoute(ProductRoute.list),
            AnyRoute(ProductRoute.detail(id: 1)),
            AnyRoute(ReviewRoute.compose(productID: 1)),
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try registry.jsonDecoder().decode([AnyRoute].self, from: data)
        #expect(decoded == original)
    }

    @Test func customTypeIDIsUsedInPayloadAndLookup() throws {
        let original = AnyRoute(RenamedRoute(value: "x"))
        #expect(original.typeID == "LegacyRoute")

        let data = try JSONEncoder().encode(original)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "LegacyRoute")

        let decoded = try registry.jsonDecoder().decode(AnyRoute.self, from: data)
        #expect(decoded == original)
    }

    @Test func unknownTypeThrows() throws {
        let data = try JSONEncoder().encode(AnyRoute(ProductRoute.list))
        var empty = RouteTypeRegistry()
        empty.register(ReviewRoute.self)
        #expect(throws: RouteCodingError.unknownRouteType("ProductRoute")) {
            try empty.jsonDecoder().decode(AnyRoute.self, from: data)
        }
    }

    @Test func missingRegistryThrows() throws {
        let data = try JSONEncoder().encode(AnyRoute(ProductRoute.list))
        #expect(throws: RouteCodingError.missingRegistry) {
            try JSONDecoder().decode(AnyRoute.self, from: data)
        }
    }

    @Test func registryIntrospection() {
        #expect(registry.contains("ProductRoute"))
        #expect(registry.contains("LegacyRoute"))
        #expect(!registry.contains("RenamedRoute"))
        #expect(Set(registry.registeredTypeIDs) == ["ProductRoute", "ReviewRoute", "LegacyRoute"])
    }
}
