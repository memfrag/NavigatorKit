/// The staged form of a ``NavigationIntent``: an ordered list of stages, each
/// a batch of state mutations applied in one transaction, followed by a
/// settling point where the executor waits for SwiftUI to catch up.
///
/// Staging exists because SwiftUI cannot materialize nested presentations
/// from a single state mutation: each presentation level needs its own
/// transaction. Everything else (tab selection + full path replacement) is
/// batched into one stage.
@MainActor
public struct ExecutionPlan {
    public internal(set) var stages: [ExecutionStage]
}

/// One transaction of the plan.
@MainActor
public struct ExecutionStage {
    public enum Kind: Sendable {
        /// Tears down presentations that conflict with what follows.
        case dismiss
        /// Tab/sidebar selection and stack path mutations, in one shot.
        case base
        /// Attaches exactly one (fully formed) presented child context.
        case present
        /// Alert or confirmation dialog on the final context.
        case overlay
    }

    /// What the executor should wait for after applying this stage.
    public enum Settling {
        case none
        /// Wait until the context's view has appeared.
        case appearance(NavigationContext)
        /// Wait until the context's view has disappeared.
        case disappearance(NavigationContext)
    }

    public let kind: Kind
    public let settling: Settling
    var mutations: [PlannedMutation]

    /// Applies all of this stage's mutations synchronously.
    public func apply() {
        for mutation in mutations {
            mutation.apply()
        }
    }
}

/// A single resolved state mutation, bound to the live tree node it targets.
@MainActor
enum PlannedMutation {
    case selectTab(TabsLayout, TabID)
    case selectSidebar(SplitLayout, AnyRoute?)
    case setPath(NavigationContext, [AnyRoute])
    case setSheet(NavigationContext, PresentedContext?)
    case setCover(NavigationContext, PresentedContext?)
    case setRootPresentation(SceneNavigator, PresentedContext?)
    case setAlert(NavigationContext, RoutedAlert?)
    case setDialog(NavigationContext, RoutedDialog?)

    func apply() {
        switch self {
        case .selectTab(let tabs, let id):
            tabs.selection = id
        case .selectSidebar(let split, let selection):
            split.sidebarSelection = selection
        case .setPath(let context, let path):
            context.path = path
        case .setSheet(let context, let presented):
            context.sheet = presented
        case .setCover(let context, let presented):
            context.fullScreenCover = presented
        case .setRootPresentation(let scene, let presented):
            scene.rootPresentation = presented
        case .setAlert(let context, let alert):
            context.alert = alert
        case .setDialog(let context, let dialog):
            context.confirmationDialog = dialog
        }
    }
}
