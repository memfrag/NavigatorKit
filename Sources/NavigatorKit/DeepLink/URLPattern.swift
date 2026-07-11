import Foundation

/// One declarative deep-link route: a URL pattern plus the intent it
/// produces.
///
/// Pattern syntax:
/// - `/products/:id` — path components; `:name` captures a parameter.
/// - `*` matches exactly one component; a trailing `**` matches the rest.
/// - `shopapp://products/:id` — constrains the scheme.
/// - `https://shop.example.com/products/:id` — constrains scheme and host.
///
/// Custom-scheme URLs are normalized so the host counts as the first path
/// component (`shopapp://products/42` has effective path `products/42`),
/// which lets one path-only pattern serve URL schemes and universal links
/// alike.
public struct URLPattern: Sendable {
    enum Component: Sendable, Equatable {
        case literal(String)
        case parameter(String)
        case wildcard
        case catchAll

        var specificity: Int {
            switch self {
            case .literal: 3
            case .parameter: 2
            case .wildcard: 1
            case .catchAll: 0
            }
        }
    }

    let scheme: String?
    let host: String?
    let components: [Component]
    let transform: @Sendable (URLParameters) throws -> NavigationIntent

    /// Total specificity used to rank simultaneous matches: literal >
    /// parameter > wildcard > catch-all, then declaration order.
    var specificity: Int {
        components.reduce(scheme == nil ? 0 : 4) { $0 + $1.specificity }
    }

    public init(
        _ pattern: String,
        intent: @escaping @Sendable (URLParameters) throws -> NavigationIntent
    ) {
        var scheme: String? = nil
        var host: String? = nil
        var remainder = Substring(pattern)

        if let range = remainder.range(of: "://") {
            scheme = String(remainder[..<range.lowerBound]).lowercased()
            remainder = remainder[range.upperBound...]
            let isWebScheme = scheme == "http" || scheme == "https"
            if isWebScheme {
                // First segment is a real host constraint.
                if let slash = remainder.firstIndex(of: "/") {
                    host = String(remainder[..<slash]).lowercased()
                    remainder = remainder[remainder.index(after: slash)...]
                } else {
                    host = String(remainder).lowercased()
                    remainder = ""
                }
            }
            // Custom schemes: the "host" is just the first effective path
            // component; leave it in the remainder.
        }

        self.scheme = scheme
        self.host = host
        self.components =
            remainder
            .split(separator: "/")
            .map { segment in
                if segment == "**" {
                    .catchAll
                } else if segment == "*" {
                    .wildcard
                } else if segment.hasPrefix(":") {
                    .parameter(String(segment.dropFirst()))
                } else {
                    .literal(String(segment))
                }
            }
        self.transform = intent
    }

    /// Matches the URL, returning captured parameters on success.
    func match(_ url: URL) -> URLParameters? {
        if let scheme, url.scheme?.lowercased() != scheme {
            return nil
        }
        if let host, url.host()?.lowercased() != host {
            return nil
        }

        let effective = Self.effectiveComponents(of: url)
        var values: [String: String] = [:]
        var catchAll: [String] = []

        var index = 0
        for component in components {
            switch component {
            case .catchAll:
                catchAll = Array(effective[index...])
                index = effective.count
            case .literal(let literal):
                guard index < effective.count, effective[index] == literal else { return nil }
                index += 1
            case .parameter(let name):
                guard index < effective.count else { return nil }
                values[name] = effective[index]
                index += 1
            case .wildcard:
                guard index < effective.count else { return nil }
                index += 1
            }
        }
        guard index == effective.count else { return nil }

        var queryItems: [String: String] = [:]
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                queryItems[item.name] = item.value ?? ""
            }
        }
        return URLParameters(values: values, queryItems: queryItems, catchAll: catchAll)
    }

    /// Path components used for matching, with the leading "/" dropped and a
    /// custom scheme's host folded in as the first component.
    static func effectiveComponents(of url: URL) -> [String] {
        let path = url.pathComponents.filter { $0 != "/" }
        let isWebScheme = url.scheme == "http" || url.scheme == "https"
        if !isWebScheme, let host = url.host(), !host.isEmpty {
            return [host] + path
        }
        return path
    }
}
