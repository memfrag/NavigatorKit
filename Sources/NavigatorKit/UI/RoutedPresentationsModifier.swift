import SwiftUI

extension View {
    /// Installs sheet / full-screen-cover / alert / confirmation-dialog
    /// bindings for a ``NavigationContext``. Applied by `RoutedStack` at
    /// every level of the tree, which is what makes nested presentation
    /// chains work: each presented context installs its own bindings.
    public func routedPresentations(_ context: NavigationContext) -> some View {
        modifier(RoutedPresentationsModifier(context: context))
    }
}

struct RoutedPresentationsModifier: ViewModifier {
    @Bindable var context: NavigationContext

    func body(content: Content) -> some View {
        content
            .sheet(item: $context.sheet) { presented in
                PresentedContentView(presented: presented)
            }
            .modifier(CoverModifier(context: context))
            .modifier(AlertModifier(context: context))
            .modifier(DialogModifier(context: context))
    }
}

/// Full-screen cover on iOS; falls back to a sheet on macOS.
private struct CoverModifier: ViewModifier {
    @Bindable var context: NavigationContext

    func body(content: Content) -> some View {
        #if os(iOS)
            content.fullScreenCover(item: $context.fullScreenCover) { presented in
                PresentedContentView(presented: presented)
            }
        #else
            // Attach to a background view so the second presentation modifier
            // does not clobber the sheet binding on the same node.
            content.background(
                Color.clear.sheet(item: $context.fullScreenCover) { presented in
                    PresentedContentView(presented: presented)
                }
            )
        #endif
    }
}

/// The content of a presented context: a recursive `RoutedStack` plus
/// presentation options and the appear/disappear signals the intent executor
/// awaits.
struct PresentedContentView: View {
    let presented: PresentedContext

    var body: some View {
        RoutedStack(context: presented.content)
            .modifier(PresentationOptionsModifier(style: presented.style))
            .onAppear { presented.content.signalDidAppear() }
            .onDisappear { presented.content.signalDidDisappear() }
    }
}

private struct PresentationOptionsModifier: ViewModifier {
    let style: PresentationStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if let options = style.sheetOptions {
            let configured =
                content
                .presentationDragIndicator(options.showsDragIndicator ? .visible : .automatic)
                .interactiveDismissDisabled(options.interactiveDismissDisabled)
            if options.detents.isEmpty {
                configured
            } else {
                configured.presentationDetents(Set(options.detents.map(\.swiftUIDetent)))
            }
        } else {
            content
        }
    }
}

extension PresentationDetentKind {
    var swiftUIDetent: PresentationDetent {
        switch self {
        case .medium: .medium
        case .large: .large
        case .fraction(let fraction): .fraction(fraction)
        case .height(let height): .height(height)
        }
    }
}

// MARK: - Alert / dialog

private struct AlertModifier: ViewModifier {
    @Bindable var context: NavigationContext

    func body(content: Content) -> some View {
        content.alert(
            context.alert?.title ?? "",
            isPresented: Binding(
                get: { context.alert != nil },
                set: { if !$0 { context.alert = nil } }
            ),
            presenting: context.alert
        ) { alert in
            ForEach(alert.buttons) { button in
                Button(button.label, role: button.role?.swiftUIRole) {
                    button.handler?()
                }
            }
        } message: { alert in
            if let message = alert.message {
                Text(message)
            }
        }
    }
}

private struct DialogModifier: ViewModifier {
    @Bindable var context: NavigationContext

    func body(content: Content) -> some View {
        content.confirmationDialog(
            context.confirmationDialog?.title ?? "",
            isPresented: Binding(
                get: { context.confirmationDialog != nil },
                set: { if !$0 { context.confirmationDialog = nil } }
            ),
            titleVisibility: context.confirmationDialog?.titleVisibility.swiftUIVisibility ?? .automatic,
            presenting: context.confirmationDialog
        ) { dialog in
            ForEach(dialog.buttons) { button in
                Button(button.label, role: button.role?.swiftUIRole) {
                    button.handler?()
                }
            }
        } message: { dialog in
            if let message = dialog.message {
                Text(message)
            }
        }
    }
}

extension RoutedAlertButton.Role {
    var swiftUIRole: ButtonRole {
        switch self {
        case .cancel: .cancel
        case .destructive: .destructive
        }
    }
}

extension RoutedDialog.TitleVisibility {
    var swiftUIVisibility: Visibility {
        switch self {
        case .automatic: .automatic
        case .visible: .visible
        case .hidden: .hidden
        }
    }
}
