import Foundation

/// Stable identity of a ``NavigationContext`` within a scene's tree.
public struct ContextID: Hashable, Sendable {
    private let raw: UUID
    public init() { self.raw = UUID() }
}

/// Identity of one scene (window) registered with the app-level coordinator.
public struct SceneID: Hashable, Sendable {
    private let raw: UUID
    public init() { self.raw = UUID() }
}

/// Identity of a tab in a ``TabsLayout``.
///
/// String-backed so tab selection is trivially `Codable` for state
/// restoration. Apps typically use a `String`-raw-value enum:
///
/// ```swift
/// enum AppTab: String { case shop, settings }
/// TabID(AppTab.shop)
/// ```
public struct TabID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init<T: RawRepresentable>(_ value: T) where T.RawValue == String {
        self.rawValue = value.rawValue
    }

    public init(from decoder: any Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
