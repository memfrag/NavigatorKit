import Foundation

/// A route-driven alert, bound by the UI layer to `.alert(item:)`-style
/// presentation on whichever ``NavigationContext`` it is set on.
///
/// Alerts are transient: they are never persisted by state restoration.
public struct RoutedAlert: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var message: String?
    public var buttons: [RoutedAlertButton]

    public init(
        _ title: String,
        message: String? = nil,
        buttons: [RoutedAlertButton] = []
    ) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.buttons = buttons
    }
}

/// A route-driven confirmation dialog (action sheet).
public struct RoutedDialog: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var message: String?
    public var titleVisibility: TitleVisibility
    public var buttons: [RoutedAlertButton]

    public enum TitleVisibility: Sendable {
        case automatic, visible, hidden
    }

    public init(
        _ title: String,
        message: String? = nil,
        titleVisibility: TitleVisibility = .automatic,
        buttons: [RoutedAlertButton] = []
    ) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.titleVisibility = titleVisibility
        self.buttons = buttons
    }
}

/// A button in a ``RoutedAlert`` or ``RoutedDialog``.
public struct RoutedAlertButton: Identifiable, Sendable {
    public let id: UUID
    public var label: String
    public var role: Role?
    public var handler: (@MainActor @Sendable () -> Void)?

    public enum Role: Sendable {
        case cancel, destructive
    }

    public init(
        _ label: String,
        role: Role? = nil,
        handler: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.id = UUID()
        self.label = label
        self.role = role
        self.handler = handler
    }

    /// A standard cancel button.
    public static func cancel(
        _ label: String = "Cancel",
        handler: (@MainActor @Sendable () -> Void)? = nil
    ) -> RoutedAlertButton {
        RoutedAlertButton(label, role: .cancel, handler: handler)
    }

    /// A destructive button.
    public static func destructive(
        _ label: String,
        handler: (@MainActor @Sendable () -> Void)? = nil
    ) -> RoutedAlertButton {
        RoutedAlertButton(label, role: .destructive, handler: handler)
    }
}
