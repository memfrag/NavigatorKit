import Foundation

/// The app's deep-link table: an ordered set of ``URLPattern``s mapping URLs
/// (custom schemes, universal links, notification payloads) to
/// ``NavigationIntent``s.
///
/// ```swift
/// static let map = DeepLinkMap {
///     URLPattern("/products/:id") { params in
///         try NavigationIntent {
///             SelectTab(AppTab.shop)
///             SetStack(ProductRoute.list, ProductRoute.detail(id: try params.id(Int.self)))
///         }
///     }
///     URLPattern("shopapp://settings/**") { _ in
///         NavigationIntent { SelectTab(AppTab.settings) }
///     }
/// }
/// ```
///
/// Matching is pure (`URL → NavigationIntent?`): the most specific matching
/// pattern wins (literal > parameter > wildcard > catch-all), with
/// declaration order as the tiebreak. A handler that throws (malformed
/// parameter) fails that pattern and matching falls through to the next.
public struct DeepLinkMap: Sendable {
    private let patterns: [URLPattern]

    public init(@DeepLinkMapBuilder _ build: () -> [URLPattern]) {
        self.patterns = build()
    }

    public init(patterns: [URLPattern]) {
        self.patterns = patterns
    }

    /// Resolves a URL to a navigation intent, or `nil` when no pattern
    /// matches.
    public func intent(for url: URL) -> NavigationIntent? {
        let ranked = patterns.enumerated().sorted {
            ($0.element.specificity, -$0.offset) > ($1.element.specificity, -$1.offset)
        }
        for (_, pattern) in ranked {
            guard let parameters = pattern.match(url) else { continue }
            if let intent = try? pattern.transform(parameters) {
                return intent
            }
            // Handler threw (e.g. malformed parameter): fall through.
        }
        return nil
    }
}

@resultBuilder
public enum DeepLinkMapBuilder {
    public static func buildExpression(_ expression: URLPattern) -> [URLPattern] {
        [expression]
    }

    public static func buildBlock(_ components: [URLPattern]...) -> [URLPattern] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [URLPattern]?) -> [URLPattern] {
        component ?? []
    }

    public static func buildEither(first component: [URLPattern]) -> [URLPattern] {
        component
    }

    public static func buildEither(second component: [URLPattern]) -> [URLPattern] {
        component
    }

    public static func buildArray(_ components: [[URLPattern]]) -> [URLPattern] {
        components.flatMap(\.self)
    }
}
