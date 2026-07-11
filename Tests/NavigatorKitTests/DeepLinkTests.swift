import Foundation
import Testing

@testable import NavigatorKit

private func url(_ string: String) -> URL {
    URL(string: string)!
}

@Suite("URLPattern matching")
struct URLPatternTests {
    private let noIntent: @Sendable (URLParameters) throws -> NavigationIntent = { _ in
        NavigationIntent(operations: [])
    }

    @Test func literalAndParameter() throws {
        let pattern = URLPattern("/products/:id", intent: noIntent)
        let params = try #require(pattern.match(url("https://example.com/products/42")))
        #expect(try params.id(Int.self) == 42)
        #expect(params["id"] == "42")

        #expect(pattern.match(url("https://example.com/products")) == nil)
        #expect(pattern.match(url("https://example.com/products/42/reviews")) == nil)
        #expect(pattern.match(url("https://example.com/orders/42")) == nil)
    }

    @Test func customSchemeHostIsFirstPathComponent() throws {
        let pattern = URLPattern("/products/:id", intent: noIntent)
        let params = try #require(pattern.match(url("shopapp://products/42")))
        #expect(try params.id(Int.self) == 42)
    }

    @Test func schemeConstraint() {
        let pattern = URLPattern("shopapp://products/:id", intent: noIntent)
        #expect(pattern.match(url("shopapp://products/1")) != nil)
        #expect(pattern.match(url("otherapp://products/1")) == nil)
        #expect(pattern.match(url("https://example.com/products/1")) == nil)
    }

    @Test func webSchemeHostConstraint() {
        let pattern = URLPattern("https://shop.example.com/products/:id", intent: noIntent)
        #expect(pattern.match(url("https://shop.example.com/products/1")) != nil)
        #expect(pattern.match(url("https://other.example.com/products/1")) == nil)
    }

    @Test func wildcardMatchesExactlyOne() {
        let pattern = URLPattern("/settings/*", intent: noIntent)
        #expect(pattern.match(url("shopapp://settings/profile")) != nil)
        #expect(pattern.match(url("shopapp://settings")) == nil)
        #expect(pattern.match(url("shopapp://settings/a/b")) == nil)
    }

    @Test func catchAllMatchesRest() throws {
        let pattern = URLPattern("/settings/**", intent: noIntent)
        let params = try #require(pattern.match(url("shopapp://settings/a/b/c")))
        #expect(params.catchAll == ["a", "b", "c"])
        // Catch-all also matches zero remaining components.
        #expect(pattern.match(url("shopapp://settings")) != nil)
    }

    @Test func queryCapture() throws {
        let pattern = URLPattern("/products/:id", intent: noIntent)
        let params = try #require(pattern.match(url("https://x.com/products/9?ref=email&promo=1")))
        #expect(params.query("ref") == "email")
        #expect(try params.query("promo", as: Bool.self) == true)
        #expect(params.query("missing") == nil)
    }

    @Test func typedExtractionErrors() throws {
        let pattern = URLPattern("/products/:id", intent: noIntent)
        let params = try #require(pattern.match(url("https://x.com/products/abc")))
        #expect(throws: DeepLinkError.invalidParameter(name: "id", value: "abc", type: "Int")) {
            try params.id(Int.self)
        }
        #expect(throws: DeepLinkError.missingParameter("bogus")) {
            try params("bogus", as: Int.self)
        }
    }

    @Test func percentEncodedComponentsAreDecoded() throws {
        let pattern = URLPattern("/tags/:name", intent: noIntent)
        let params = try #require(pattern.match(url("https://x.com/tags/hello%20world")))
        #expect(params["name"] == "hello world")
    }
}

@Suite("DeepLinkMap")
struct DeepLinkMapTests {
    private static let map = DeepLinkMap {
        URLPattern("/products/**") { _ in
            NavigationIntent { SelectTab(AppTab.shop) }
        }
        URLPattern("/products/:id") { params in
            try NavigationIntent {
                SelectTab(AppTab.shop)
                SetStack(ProductRoute.list, ProductRoute.detail(id: try params.id(Int.self)))
            }
        }
        URLPattern("/settings/**") { _ in
            NavigationIntent { SelectTab(AppTab.settings) }
        }
    }

    @Test func mostSpecificPatternWinsRegardlessOfOrder() throws {
        // "/products/42" matches both the catch-all and ":id" patterns; the
        // parameter pattern is more specific even though declared later.
        let intent = try #require(Self.map.intent(for: url("shopapp://products/42")))
        #expect(intent.operations.count == 2)
        if case .setPath(let path) = intent.operations[1] {
            #expect(path == [AnyRoute(ProductRoute.list), AnyRoute(ProductRoute.detail(id: 42))])
        } else {
            Issue.record("Expected setPath from the :id pattern")
        }
    }

    @Test func throwingHandlerFallsThroughToNextMatch() throws {
        // "abc" fails Int extraction in the :id pattern → catch-all handles it.
        let intent = try #require(Self.map.intent(for: url("shopapp://products/abc")))
        #expect(intent.operations.count == 1)
    }

    @Test func noMatchReturnsNil() {
        #expect(Self.map.intent(for: url("shopapp://unknown/path")) == nil)
    }

    @Test func universalLinkAndCustomSchemeHitSamePattern() throws {
        let fromWeb = try #require(Self.map.intent(for: url("https://shop.example.com/products/7")))
        let fromScheme = try #require(Self.map.intent(for: url("shopapp://products/7")))
        #expect(fromWeb.operations.count == fromScheme.operations.count)
    }
}
