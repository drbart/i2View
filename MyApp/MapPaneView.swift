import SwiftUI

struct MapSearchBar: View {
    @Binding var query: String
    let placeholder: String
    let isSearching: Bool
    let results: [SearchResultItem]
    let onSelectResult: (SearchResultItem) -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $query)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { item in
                        Button {
                            isFocused = false
                            onSelectResult(item)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.caption)
                                Text(item.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item.id != results.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
        }
    }
}

struct DividerBar: View {
    let isLandscape: Bool
    @Bindable var viewModel: DualMapViewModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(uiColor: .systemGroupedBackground))
                .shadow(radius: 3)

            Button(action: viewModel.toggleLock) {
                Image(systemName: viewModel.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(viewModel.isLocked ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .frame(
            width: isLandscape ? 24 : nil,
            height: isLandscape ? nil : 24
        )
    }
}

struct MapPaneView: View {
    let mapIndex: Int
    @Bindable var viewModel: DualMapViewModel
    @State private var locationManager = LocationManager()

    private var targetPosition: MapPosition {
        mapIndex == 1 ? viewModel.map1Position : viewModel.map2Position
    }

    private var searchQuery: Binding<String> {
        Binding(
            get: { mapIndex == 1 ? viewModel.map1SearchQuery : viewModel.map2SearchQuery },
            set: { viewModel.performSearch(mapIndex: mapIndex, query: $0) }
        )
    }

    var body: some View {
        ZStack {
            // 1. Map Canvas Engine
            if viewModel.mapEngine == .appleMaps {
                AppleMapsView(position: targetPosition) { newPos, isUser in
                    if mapIndex == 1 {
                        viewModel.updateMap1Position(newPos, isUserGesture: isUser)
                    } else {
                        viewModel.updateMap2Position(newPos, isUserGesture: isUser)
                    }
                }
            } else {
                OpenStreetMapTileView(position: targetPosition) { newPos, isUser in
                    if mapIndex == 1 {
                        viewModel.updateMap1Position(newPos, isUserGesture: isUser)
                    } else {
                        viewModel.updateMap2Position(newPos, isUserGesture: isUser)
                    }
                }
            }

            // 2. Top Center Overlay Search Bar
            VStack {
                MapSearchBar(
                    query: searchQuery,
                    placeholder: "Search",
                    isSearching: mapIndex == 1 ? viewModel.map1IsSearching : viewModel.map2IsSearching,
                    results: mapIndex == 1 ? viewModel.map1SearchResults : viewModel.map2SearchResults,
                    onSelectResult: { result in
                        viewModel.onSearchResultSelected(mapIndex: mapIndex, result: result)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()
            }

            // 3. Bottom Right Control Stack (Zoom In, Zoom Out, My Location)
            VStack(alignment: .trailing, spacing: 6) {
                Spacer()

                HStack {
                    Spacer()

                    VStack(spacing: 6) {
                        // Zoom In (+)
                        Button {
                            let newZoom = min(targetPosition.zoom + 1.0, 20.0)
                            var updated = targetPosition
                            updated.zoom = newZoom
                            if mapIndex == 1 {
                                viewModel.updateMap1Position(updated, isUserGesture: true)
                            } else {
                                viewModel.updateMap2Position(updated, isUserGesture: true)
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        }

                        // Zoom Out (-)
                        Button {
                            let newZoom = max(targetPosition.zoom - 1.0, 2.0)
                            var updated = targetPosition
                            updated.zoom = newZoom
                            if mapIndex == 1 {
                                viewModel.updateMap1Position(updated, isUserGesture: true)
                            } else {
                                viewModel.updateMap2Position(updated, isUserGesture: true)
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        }

                        // My Location
                        Button {
                            locationManager.requestLocation { coordinate in
                                let userPos = MapPosition(
                                    latitude: coordinate.latitude,
                                    longitude: coordinate.longitude,
                                    zoom: 15.0
                                )
                                if mapIndex == 1 {
                                    viewModel.updateMap1Position(userPos, isUserGesture: true)
                                } else {
                                    viewModel.updateMap2Position(userPos, isUserGesture: true)
                                }
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .clipped()
    }
}
