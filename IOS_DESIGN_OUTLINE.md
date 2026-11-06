# 2View iOS Technical Design & Architecture Guide

A comprehensive architectural and design outline for implementing the **2View** dual-map comparison application for iOS using Xcode, Swift, and SwiftUI.

---

## 1. Executive Summary & Goals

**2View** is a dual-viewport map comparison application enabling users to inspect, compare, and synchronize two geographic locations side-by-side or stacked vertically.

### Key Product Features
- **Responsive Dual Panes**: Stacked vertically in Portrait, side-by-side in Landscape.
- **Camera Lock & Sync**:
  - **Zoom Level Syncing**: Locking synchronizes only the zoom factor of the least recently moved map to the most recently moved map, preserving distinct locations.
  - **Relative / Exact Sync Modes**: Locked movement maintains relative offset or exact location copies.
- **Search Unlocking**: Any search operation automatically unlocks the cameras so searching on one map pane never alters the other map.
- **Unified Engine Switch**: Single top navigation bar control to toggle between Apple Maps (MapKit) and OpenStreetMap (OSM).
- **Embedded Control Stack**: Floating Zoom In (`+`), Zoom Out (`-`), and My Location buttons on each pane.
- **Resilient Search**: Primary geocoding via Apple `CLGeocoder` with fallback to OpenStreetMap Nominatim REST API via `URLSession`.

---

## 2. iOS Technology Stack & Architecture

| Component | Technology / Framework |
| :--- | :--- |
| **Language** | Swift 5.9+ |
| **UI Framework** | SwiftUI (iOS 17+ target) |
| **Architecture** | MVVM with `@Observable` / Combine |
| **Map Rendering** | `MapKit` (Apple Maps) & `MKTileOverlay` or `WKWebView` / `MapLibre` (OSM) |
| **Location Services** | `CoreLocation` (`CLLocationManager`) |
| **Networking** | Native `URLSession` with `async/await` |

---

## 3. Data Models & Core Types

### `MapPosition`
Represents camera position for a map pane.

```swift
import CoreLocation

struct MapPosition: Equatable {
    var latitude: Double
    var longitude: Double
    var zoom: Double          // Range: 2.0 (world) to 20.0 (building)
    var pitch: Double = 0.0   // Tilt in degrees
    var heading: Double = 0.0 // Bearing in degrees

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let defaultMap1 = MapPosition(latitude: 37.7749, longitude: -122.4194, zoom: 12.0) // San Francisco
    static let defaultMap2 = MapPosition(latitude: 51.5074, longitude: -0.1278, zoom: 12.0)   // London
}
```

### `SearchResultItem`
Location search result model.

```swift
struct SearchResultItem: Identifiable, Equatable {
    let id = UUID()
    let displayName: String
    let latitude: Double
    let longitude: Double
}
```

### Enums
```swift
enum MapEngine {
    case appleMaps
    case openStreetMap
}

enum SyncMode {
    case exact
    case relative
}
```

---

## 4. ViewModel State & Synchronization Logic

### `@Observable` ViewModel Definition (`DualMapViewModel.swift`)

```swift
import SwiftUI
import CoreLocation
import Combine

@Observable
final class DualMapViewModel {
    // UI State
    var isLocked: Bool = false
    var map1Position: MapPosition = .defaultMap1
    var map2Position: MapPosition = .defaultMap2
    var syncMode: SyncMode = .relative
    var mapEngine: MapEngine = .openStreetMap
    var lastMovedMap: Int = 1 // 1 or 2

    // Search States
    var map1SearchQuery: String = ""
    var map2SearchQuery: String = ""
    var map1SearchResults: [SearchResultItem] = []
    var map2SearchResults: [SearchResultItem] = []
    var map1IsSearching: Bool = false
    var map2IsSearching: Bool = false

    private var isSyncing: Bool = false
    private var searchTaskMap1: Task<Void, Never>?
    private var searchTaskMap2: Task<Void, Never>?

    // MARK: - Lock Logic
    func toggleLock() {
        let newLockState = !isLocked
        if newLockState {
            // Lock activated: Sync zoom factor of least-recently-moved map to most-recently-moved map
            let targetZoom = (lastMovedMap == 1) ? map1Position.zoom : map2Position.zoom

            if lastMovedMap == 1 {
                map2Position.zoom = targetZoom
            } else {
                map1Position.zoom = targetZoom
            }
            isLocked = true
        } else {
            isLocked = false
        }
    }

    // MARK: - Camera Movement Logic
    func updateMap1Position(_ newPos: MapPosition, isUserGesture: Bool) {
        if isSyncing {
            map1Position = newPos
            return
        }

        if isUserGesture { lastMovedMap = 1 }

        if isLocked && isUserGesture {
            isSyncing = true
            defer { isSyncing = false }

            let syncedMap2 = calculateSyncedPosition(
                sourceNew: newPos,
                sourceOld: map1Position,
                targetOld: map2Position,
                mode: syncMode
            )
            map1Position = newPos
            map2Position = syncedMap2
        } else {
            map1Position = newPos
        }
    }

    func updateMap2Position(_ newPos: MapPosition, isUserGesture: Bool) {
        if isSyncing {
            map2Position = newPos
            return
        }

        if isUserGesture { lastMovedMap = 2 }

        if isLocked && isUserGesture {
            isSyncing = true
            defer { isSyncing = false }

            let syncedMap1 = calculateSyncedPosition(
                sourceNew: newPos,
                sourceOld: map2Position,
                targetOld: map1Position,
                mode: syncMode
            )
            map2Position = newPos
            map1Position = syncedMap1
        } else {
            map2Position = newPos
        }
    }

    private func calculateSyncedPosition(
        sourceNew: MapPosition,
        sourceOld: MapPosition,
        targetOld: MapPosition,
        mode: SyncMode
    ) -> MapPosition {
        switch mode {
        case .exact:
            return sourceNew
        case .relative:
            let deltaLat = sourceNew.latitude - sourceOld.latitude
            let deltaLng = sourceNew.longitude - sourceOld.longitude
            let deltaZoom = sourceNew.zoom - sourceOld.zoom

            var newLat = (targetOld.latitude + deltaLat).clamped(to: -85.0...85.0)
            var newLng = targetOld.longitude + deltaLng
            while newLng > 180.0 { newLng -= 360.0 }
            while newLng < -180.0 { newLng += 360.0 }

            let newZoom = (targetOld.zoom + deltaZoom).clamped(to: 2.0...20.0)
            return MapPosition(
                latitude: newLat,
                longitude: newLng,
                zoom: newZoom,
                pitch: sourceNew.pitch,
                heading: sourceNew.heading
            )
        }
    }

    func resetPositions() {
        if isLocked {
            map1Position = .defaultMap1
            map2Position = (syncMode == .exact) ? .defaultMap1 : .defaultMap2
        } else {
            map1Position = .defaultMap1
            map2Position = .defaultMap2
        }
    }

    // MARK: - Search & Auto-Unlock Rule
    func performSearch(mapIndex: Int, query: String) {
        // Rule: Any search automatically disables camera lock
        if isLocked { isLocked = false }

        if mapIndex == 1 {
            searchTaskMap1?.cancel()
        } else {
            searchTaskMap2?.cancel()
        }

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearSearchResults(mapIndex: mapIndex)
            return
        }

        let task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms Debounce
            if Task.isCancelled { return }

            await MainActor.run {
                if mapIndex == 1 { map1IsSearching = true } else { map2IsSearching = true }
            }

            let results = await searchLocationService(query: query)
            if Task.isCancelled { return }

            await MainActor.run {
                if mapIndex == 1 {
                    map1SearchResults = results
                    map1IsSearching = false
                } else {
                    map2SearchResults = results
                    map2IsSearching = false
                }
            }
        }

        if mapIndex == 1 { searchTaskMap1 = task } else { searchTaskMap2 = task }
    }

    func onSearchResultSelected(mapIndex: Int, result: SearchResultItem) {
        if isLocked { isLocked = false }

        let targetZoom = (mapIndex == 1) ? max(map1Position.zoom, 14.0) : max(map2Position.zoom, 14.0)
        let newPos = MapPosition(latitude: result.latitude, longitude: result.longitude, zoom: targetZoom)

        if mapIndex == 1 {
            updateMap1Position(newPos, isUserGesture: true)
            map1SearchQuery = result.displayName
            map1SearchResults = []
        } else {
            updateMap2Position(newPos, isUserGesture: true)
            map2SearchQuery = result.displayName
            map2SearchResults = []
        }
    }
}
```

---

## 5. UI Layout & View Hierarchy

### Root View (`DualMapContentView.swift`)

```swift
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
            .navigationTitle("2View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Engine Switcher
                    Button(viewModel.mapEngine == .appleMaps ? "Apple" : "OSM") {
                        viewModel.mapEngine = (viewModel.mapEngine == .appleMaps) ? .openStreetMap : .appleMaps
                    }

                    // Sync Mode Switcher
                    Button(viewModel.syncMode == .exact ? "EXACT" : "RELATIVE") {
                        viewModel.syncMode = (viewModel.syncMode == .exact) ? .relative : .exact
                    }

                    // Reset Positions Button
                    Button(action: viewModel.resetPositions) {
                        Image(systemName: "arrow.clockwise")
                    }

                    // Lock Button
                    Button(action: viewModel.toggleLock) {
                        Image(systemName: viewModel.isLocked ? "lock.fill" : "lock.open")
                            .foregroundColor(viewModel.isLocked ? .accentColor : .secondary)
                    }
                }
            }
        }
    }
}
```

### Separator / Lock Bar (`DividerBar.swift`)

Narrow `24 pt` floating separator bar with center lock button.

```swift
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
                    .foregroundColor(viewModel.isLocked ? .accentColor : .secondary)
            }
        }
        .frame(
            width: isLandscape ? 24 : nil,
            height: isLandscape ? nil : 24
        )
    }
}
```

---

## 6. Map Pane & Overlay Controls (`MapPaneView.swift`)

Each map pane encapsulates the map tile canvas, floating search bar, and stacked action controls (Zoom In, Zoom Out, My Location).

```swift
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
                        viewModel.updateMap1Position(newPos, isUser)
                    } else {
                        viewModel.updateMap2Position(newPos, isUser)
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
                            if mapIndex == 1 { viewModel.updateMap1Position(updated, isUserGesture: true) }
                            else { viewModel.updateMap2Position(updated, isUserGesture: true) }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                        }

                        // Zoom Out (-)
                        Button {
                            let newZoom = max(targetPosition.zoom - 1.0, 2.0)
                            var updated = targetPosition
                            updated.zoom = newZoom
                            if mapIndex == 1 { viewModel.updateMap1Position(updated, isUserGesture: true) }
                            else { viewModel.updateMap2Position(updated, isUserGesture: true) }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                        }

                        // My Location
                        Button {
                            locationManager.requestLocation { coordinate in
                                let userPos = MapPosition(latitude: coordinate.latitude, longitude: coordinate.longitude, zoom: 15.0)
                                if mapIndex == 1 { viewModel.updateMap1Position(userPos, isUserGesture: true) }
                                else { viewModel.updateMap2Position(userPos, isUserGesture: true) }
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .clipToBounds()
    }
}
```

---

## 7. Geocoding Service Implementation

Location search combines Apple's native `CLGeocoder` with an HTTP fallback to OpenStreetMap Nominatim API via `URLSession`.

```swift
func searchLocationService(query: String) async -> [SearchResultItem] {
    // 1. Try Apple Native CLGeocoder
    if let geocoderResults = try? await geocodeWithCLGeocoder(query: query), !geocoderResults.isEmpty {
        return geocoderResults
    }

    // 2. Fallback to OpenStreetMap Nominatim REST API
    return await geocodeWithNominatim(query: query)
}

private func geocodeWithCLGeocoder(query: String) async throws -> [SearchResultItem] {
    let geocoder = CLGeocoder()
    let placemarks = try await geocoder.geocodeAddressString(query)
    return placemarks.compactMap { placemark -> SearchResultItem? in
        guard let location = placemark.location else { return nil }
        let name = [placemark.name, placemark.locality, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
        return SearchResultItem(displayName: name.isEmpty ? query : name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

private func geocodeWithNominatim(query: String) async -> [SearchResultItem] {
    guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://nominatim.openstreetmap.org/search?format=json&q=\(encoded)&limit=5") else {
        return []
    }

    var request = URLRequest(url: url)
    request.setValue("2ViewIOS/1.0 (iOS Map Viewer)", forHTTPHeaderField: "User-Agent")

    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }

    return jsonArray.compactMap { dict -> SearchResultItem? in
        guard let name = dict["display_name"] as? String,
              let latStr = dict["lat"] as? String, let lat = Double(latStr),
              let lonStr = dict["lon"] as? String, let lon = Double(lonStr) else { return nil }
        return SearchResultItem(displayName: name, latitude: lat, longitude: lon)
    }
}
```

---

## 8. Xcode Project Checklist

1. **Info.plist Location Permissions**:
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>2View uses your location to center the map pane on your current position.</string>
   ```
2. **App Icon Asset**:
   Create adaptive App Icon in `Assets.xcassets` matching the 2View dual-map & lock icon design.
3. **Build Target**: iOS 17.0+ (SwiftUI `@Observable` macro support).
