/// How a child ``NavigationContext`` is presented over its parent.
///
/// Modeled independently of SwiftUI so the state layer stays headless and
/// `Codable` for restoration; the UI layer maps these onto `.sheet`,
/// `.fullScreenCover`, and presentation-detent modifiers.
public struct PresentationStyle: Hashable, Sendable, Codable {
    enum Kind: Hashable, Sendable, Codable {
        case sheet(SheetOptions)
        case fullScreenCover
    }

    let kind: Kind

    /// A sheet presentation.
    public static func sheet(
        detents: [PresentationDetentKind] = [],
        showsDragIndicator: Bool = false,
        interactiveDismissDisabled: Bool = false
    ) -> PresentationStyle {
        PresentationStyle(
            kind: .sheet(
                SheetOptions(
                    detents: detents,
                    showsDragIndicator: showsDragIndicator,
                    interactiveDismissDisabled: interactiveDismissDisabled
                )
            )
        )
    }

    /// A full-screen cover (falls back to a sheet on macOS, where
    /// `fullScreenCover` does not exist).
    public static let fullScreenCover = PresentationStyle(kind: .fullScreenCover)

    /// Whether this style occupies the full-screen-cover presentation slot.
    public var isFullScreenCover: Bool {
        if case .fullScreenCover = kind { return true }
        return false
    }

    var sheetOptions: SheetOptions? {
        if case .sheet(let options) = kind { return options }
        return nil
    }
}

/// Options applied to a sheet presentation.
public struct SheetOptions: Hashable, Sendable, Codable {
    /// Presentation detents; empty means the platform default.
    public var detents: [PresentationDetentKind]
    public var showsDragIndicator: Bool
    public var interactiveDismissDisabled: Bool

    public init(
        detents: [PresentationDetentKind] = [],
        showsDragIndicator: Bool = false,
        interactiveDismissDisabled: Bool = false
    ) {
        self.detents = detents
        self.showsDragIndicator = showsDragIndicator
        self.interactiveDismissDisabled = interactiveDismissDisabled
    }
}

/// A `Codable` mirror of SwiftUI's `PresentationDetent`.
public enum PresentationDetentKind: Hashable, Sendable, Codable {
    case medium
    case large
    case fraction(Double)
    case height(Double)
}
