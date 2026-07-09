import SwiftUI

/// Editor window content: toolbar over canvas.
struct EditorRootView: View {
    let viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(viewModel: viewModel)
            Divider()
            HStack(spacing: 0) {
                EditorCanvasView(viewModel: viewModel)
                    .background(Color(nsColor: .underPageBackgroundColor))
                if viewModel.showInspector {
                    Divider()
                    InspectorView(viewModel: viewModel)
                }
            }
        }
    }
}
