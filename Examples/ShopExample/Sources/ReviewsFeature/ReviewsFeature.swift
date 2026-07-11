import NavigatorKit
import ReviewsInterface
import SwiftUI

public struct ReviewsFeature: RoutableFeature {
    public static var destinations: DestinationGroup {
        Destination(for: ReviewRoute.self) { route in
            switch route {
            case .compose(let productID):
                ComposeReviewView(productID: productID)
            case .photoPicker:
                PhotoPickerStubView()
            }
        }
        // Reviews present as a sheet by default — declared here, so callers
        // don't need to know.
        .placement(.sheet(detents: [.medium, .large]))
    }
}

// MARK: - Views

struct ComposeReviewView: View {
    let productID: Int

    @Environment(Navigator.self) private var navigator
    @State private var text = ""

    var body: some View {
        Form {
            Section("Review for product #\(productID)") {
                TextField("What did you think?", text: $text, axis: .vertical)
                    .lineLimit(4...)
            }
            Section {
                // Nested presentation: a sheet from within a sheet.
                Button("Add Photo…") {
                    navigator.present(ReviewRoute.photoPicker)
                }
                Button("Submit") {
                    navigator.dismiss()
                    navigator.alert("Thanks!", message: "Your review was submitted.")
                }
            }
        }
        .navigationTitle("New Review")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if text.isEmpty {
                        navigator.dismiss()
                    } else {
                        navigator.confirmationDialog(
                            "Discard this review?",
                            buttons: [
                                .destructive("Discard") { navigator.dismiss() },
                                .cancel(),
                            ]
                        )
                    }
                }
            }
        }
    }
}

struct PhotoPickerStubView: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        ContentUnavailableView {
            Label("Photo Picker", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("A nested sheet, two presentation levels deep.")
        } actions: {
            Button("Done") { navigator.dismiss() }
        }
    }
}
