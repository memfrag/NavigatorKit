import Foundation

/// A `Codable` value mirror of a scene's navigation tree, used for state
/// restoration. Alerts and confirmation dialogs are transient and never
/// persisted.
///
/// Container *shape* (tabs, splits) is not restored from the snapshot — it
/// always comes from the ``SceneBlueprint`` — only selections, paths, and
/// presentations are. A snapshot whose shape no longer matches the blueprint
/// degrades gracefully: mismatched subtrees are skipped.
public struct NavigationSnapshot: Codable, Sendable, Equatable {
    /// Format version; snapshots from other versions are discarded.
    public var version: Int
    public var root: RootSnapshot
    /// The presentation chain stacked over the whole root, outermost first.
    public var rootPresentedChain: [PresentedLayerSnapshot]

    public static let currentVersion = 1

    public init(root: RootSnapshot, rootPresentedChain: [PresentedLayerSnapshot] = []) {
        self.version = Self.currentVersion
        self.root = root
        self.rootPresentedChain = rootPresentedChain
    }
}

/// Mirror of ``RootLayout``.
public enum RootSnapshot: Codable, Sendable, Equatable {
    case stack(ContextSnapshot)
    case tabs(TabsSnapshot)
    case split(SplitSnapshot)
}

/// Mirror of ``TabsLayout``.
public struct TabsSnapshot: Codable, Sendable, Equatable {
    public var selection: TabID
    public var tabs: [Entry]

    public struct Entry: Codable, Sendable, Equatable {
        public var id: TabID
        public var content: RootSnapshot

        public init(id: TabID, content: RootSnapshot) {
            self.id = id
            self.content = content
        }
    }

    public init(selection: TabID, tabs: [Entry]) {
        self.selection = selection
        self.tabs = tabs
    }
}

/// Mirror of ``SplitLayout``. The sidebar root is blueprint-owned and not
/// persisted; the selection decodes leniently (an unknown selection route
/// becomes `nil`).
public struct SplitSnapshot: Sendable, Equatable {
    public var columnVisibility: SplitColumnVisibility
    public var sidebarSelection: AnyRoute?
    public var detail: ContextSnapshot

    public init(
        columnVisibility: SplitColumnVisibility,
        sidebarSelection: AnyRoute?,
        detail: ContextSnapshot
    ) {
        self.columnVisibility = columnVisibility
        self.sidebarSelection = sidebarSelection
        self.detail = detail
    }
}

extension SplitSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case columnVisibility, sidebarSelection, detail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.columnVisibility = try container.decode(SplitColumnVisibility.self, forKey: .columnVisibility)
        do {
            self.sidebarSelection = try container.decodeIfPresent(AnyRoute.self, forKey: .sidebarSelection)
        } catch {
            decoder.restorationIssues?.record(error)
            self.sidebarSelection = nil
        }
        self.detail = try container.decode(ContextSnapshot.self, forKey: .detail)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(columnVisibility, forKey: .columnVisibility)
        try container.encodeIfPresent(sidebarSelection, forKey: .sidebarSelection)
        try container.encode(detail, forKey: .detail)
    }
}

/// Mirror of one ``NavigationContext``: its path plus the linear chain of
/// presentations stacked over it (each presented context's own presentation
/// is simply the next element).
public struct ContextSnapshot: Sendable, Equatable {
    /// Informational; base context roots come from the blueprint on restore.
    public var root: AnyRoute?
    public var path: [AnyRoute]
    public var presentedChain: [PresentedLayerSnapshot]

    public init(root: AnyRoute? = nil, path: [AnyRoute] = [], presentedChain: [PresentedLayerSnapshot] = []) {
        self.root = root
        self.path = path
        self.presentedChain = presentedChain
    }
}

extension ContextSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case root, path, presentedChain
    }

    /// Lenient decoding: an undecodable route (unregistered type) truncates
    /// the path before it and drops every presentation stacked above; an
    /// undecodable presented layer drops itself and the rest of the chain.
    /// The user lands somewhere sensible instead of restoration failing
    /// wholesale.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let issues = decoder.restorationIssues

        do {
            self.root = try container.decodeIfPresent(AnyRoute.self, forKey: .root)
        } catch {
            issues?.record(error)
            self.root = nil
            self.path = []
            self.presentedChain = []
            return
        }

        var path: [AnyRoute] = []
        var pathTruncated = false
        if var pathContainer = try? container.nestedUnkeyedContainer(forKey: .path) {
            while !pathContainer.isAtEnd {
                do {
                    path.append(try pathContainer.decode(AnyRoute.self))
                } catch {
                    issues?.record(error)
                    pathTruncated = true
                    break
                }
            }
        }
        self.path = path

        guard !pathTruncated else {
            // The view the presentations were stacked on is gone.
            self.presentedChain = []
            return
        }

        var chain: [PresentedLayerSnapshot] = []
        if var chainContainer = try? container.nestedUnkeyedContainer(forKey: .presentedChain) {
            while !chainContainer.isAtEnd {
                do {
                    let layer = try chainContainer.decode(PresentedLayerSnapshot.self)
                    chain.append(layer)
                    if layer.pathWasTruncated { break }
                } catch {
                    issues?.record(error)
                    break
                }
            }
        }
        self.presentedChain = chain
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(root, forKey: .root)
        try container.encode(path, forKey: .path)
        try container.encode(presentedChain, forKey: .presentedChain)
    }
}

/// One presented level: how it is shown plus its content stack.
public struct PresentedLayerSnapshot: Sendable, Equatable {
    public var style: PresentationStyle
    public var root: AnyRoute?
    public var path: [AnyRoute]

    /// Transient decode flag: the layer's path was truncated, so anything
    /// presented above it must be dropped.
    var pathWasTruncated = false

    public init(style: PresentationStyle, root: AnyRoute?, path: [AnyRoute] = []) {
        self.style = style
        self.root = root
        self.path = path
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style && lhs.root == rhs.root && lhs.path == rhs.path
    }
}

extension PresentedLayerSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case style, root, path
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let issues = decoder.restorationIssues

        self.style = try container.decode(PresentationStyle.self, forKey: .style)
        // A layer whose root is gone is meaningless: fail the layer (the
        // enclosing chain drops it and everything above).
        self.root = try container.decodeIfPresent(AnyRoute.self, forKey: .root)

        var path: [AnyRoute] = []
        if var pathContainer = try? container.nestedUnkeyedContainer(forKey: .path) {
            while !pathContainer.isAtEnd {
                do {
                    path.append(try pathContainer.decode(AnyRoute.self))
                } catch {
                    issues?.record(error)
                    self.pathWasTruncated = true
                    break
                }
            }
        }
        self.path = path
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(root, forKey: .root)
        try container.encode(path, forKey: .path)
    }
}

// MARK: - Issue collection

/// Collects route types dropped during lenient snapshot decoding.
final class RestorationIssueCollector {
    private(set) var droppedRouteTypeIDs: [String] = []

    func record(_ error: any Error) {
        if case RouteCodingError.unknownRouteType(let typeID) = error {
            droppedRouteTypeIDs.append(typeID)
        } else {
            droppedRouteTypeIDs.append("<undecodable route: \(error)>")
        }
    }
}

extension CodingUserInfoKey {
    static let restorationIssues = CodingUserInfoKey(rawValue: "NavigatorKit.restorationIssues")!
}

extension Decoder {
    var restorationIssues: RestorationIssueCollector? {
        userInfo[.restorationIssues] as? RestorationIssueCollector
    }
}

/// What lenient decoding had to drop while restoring.
public struct RestorationReport: Sendable, Equatable {
    /// Route type identifiers (or descriptions) that could not be decoded.
    public let droppedRouteTypeIDs: [String]

    public var isClean: Bool { droppedRouteTypeIDs.isEmpty }
}
