import Foundation

/// Values captured while matching a URL against a ``URLPattern``: named path
/// parameters, query items, and any components consumed by a `**` catch-all.
///
/// Typed extraction throws, so a malformed value ("products/abc" where an
/// `Int` is expected) fails the pattern cleanly and lets matching fall
/// through to the next pattern:
///
/// ```swift
/// URLPattern("/products/:id") { params in
///     NavigationIntent {
///         SetStack(ProductRoute.list, ProductRoute.detail(id: try params.id(Int.self)))
///     }
/// }
/// ```
@dynamicMemberLookup
public struct URLParameters: Sendable {
    private let values: [String: String]
    private let queryItems: [String: String]

    /// Path components consumed by a trailing `**` catch-all.
    public let catchAll: [String]

    init(values: [String: String], queryItems: [String: String], catchAll: [String] = []) {
        self.values = values
        self.queryItems = queryItems
        self.catchAll = catchAll
    }

    /// The raw string value of a named path parameter.
    public subscript(name: String) -> String? {
        values[name]
    }

    /// Typed extraction of a named path parameter.
    public func callAsFunction<T: URLParameterValue>(_ name: String, as type: T.Type) throws -> T {
        guard let raw = values[name] else {
            throw DeepLinkError.missingParameter(name)
        }
        guard let value = T(urlParameterValue: raw) else {
            throw DeepLinkError.invalidParameter(name: name, value: raw, type: "\(T.self)")
        }
        return value
    }

    /// `try params.id(Int.self)` sugar for ``callAsFunction(_:as:)``.
    public subscript(dynamicMember name: String) -> ParameterAccessor {
        ParameterAccessor(name: name, parameters: self)
    }

    /// The raw string value of a query item.
    public func query(_ name: String) -> String? {
        queryItems[name]
    }

    /// Typed extraction of a query item.
    public func query<T: URLParameterValue>(_ name: String, as type: T.Type) throws -> T {
        guard let raw = queryItems[name] else {
            throw DeepLinkError.missingParameter(name)
        }
        guard let value = T(urlParameterValue: raw) else {
            throw DeepLinkError.invalidParameter(name: name, value: raw, type: "\(T.self)")
        }
        return value
    }

    public struct ParameterAccessor: Sendable {
        let name: String
        let parameters: URLParameters

        public func callAsFunction<T: URLParameterValue>(_ type: T.Type) throws -> T {
            try parameters(name, as: type)
        }
    }
}

/// Types extractable from a URL path parameter or query item.
public protocol URLParameterValue: Sendable {
    init?(urlParameterValue: String)
}

extension String: URLParameterValue {
    public init?(urlParameterValue: String) { self = urlParameterValue }
}

extension Int: URLParameterValue {
    public init?(urlParameterValue: String) { self.init(urlParameterValue) }
}

extension Double: URLParameterValue {
    public init?(urlParameterValue: String) { self.init(urlParameterValue) }
}

extension Bool: URLParameterValue {
    public init?(urlParameterValue: String) {
        switch urlParameterValue.lowercased() {
        case "true", "1", "yes": self = true
        case "false", "0", "no": self = false
        default: return nil
        }
    }
}

extension UUID: URLParameterValue {
    public init?(urlParameterValue: String) { self.init(uuidString: urlParameterValue) }
}

/// Errors thrown during typed deep-link parameter extraction.
public enum DeepLinkError: Error, Sendable, Equatable {
    case missingParameter(String)
    case invalidParameter(name: String, value: String, type: String)
}
