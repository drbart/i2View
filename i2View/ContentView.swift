import SwiftUI

struct DualMapContentView: View {
    @State private var viewModel = DualMapViewModel()

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height

                Group {
                    if isLandscape {
                        HStack(spacing: 0) {
                            MapPaneView(mapIndex: 1, viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()

                            DividerBar(isLandscape: true, viewModel: viewModel)
                                .zIndex(10)

                            MapPaneView(mapIndex: 2, viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    } else {
                        VStack(spacing: 0) {
                            MapPaneView(mapIndex: 1, viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()

                            DividerBar(isLandscape: false, viewModel: viewModel)
                                .zIndex(10)

                            MapPaneView(mapIndex: 2, viewModel: viewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                    }
                }
            }
            .navigationTitle("i2View")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Engine Switcher
                    Button(viewModel.mapEngine == .appleMaps ? "Apple" : "OSM") {
                        viewModel.mapEngine = (viewModel.mapEngine == .appleMaps) ? .openStreetMap : .appleMaps
                    }
                    .font(.caption.weight(.semibold))

                    // Sync Mode Switcher
                    Button(viewModel.syncMode == .exact ? "EXACT" : "RELATIVE") {
                        viewModel.syncMode = (viewModel.syncMode == .exact) ? .relative : .exact
                    }
                    .font(.caption.weight(.semibold))

                    // Reset Positions Button
                    Button(action: viewModel.resetPositions) {
                        Image(systemName: "arrow.clockwise")
                    }

                    // Lock Button
                    Button(action: viewModel.toggleLock) {
                        Image(systemName: viewModel.isLocked ? "lock.fill" : "lock.open")
                            .foregroundStyle(viewModel.isLocked ? Color.accentColor : Color.secondary)
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        DualMapContentView()
    }
}

#Preview {
    ContentView()
}
