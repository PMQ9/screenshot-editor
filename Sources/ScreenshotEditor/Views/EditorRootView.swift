import SwiftUI

/// Editor window content: toolbar over canvas.
struct EditorRootView: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(viewModel: viewModel)
            Divider()
            EditorCanvasView(viewModel: viewModel)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
    }
}
