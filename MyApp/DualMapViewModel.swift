import SwiftUI
import CoreLocation
import MapKit
import Observation

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

            let newLat = (targetOld.latitude + deltaLat).clamped(to: -85.0...85.0)
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
    func clearSearchResults(mapIndex: Int) {
        if mapIndex == 1 {
            map1SearchResults = []
            map1IsSearching = false
        } else {
            map2SearchResults = []
            map2IsSearching = false
        }
    }

    func performSearch(mapIndex: Int, query: String) {
        if mapIndex == 1 {
            map1SearchQuery = query
            searchTaskMap1?.cancel()
        } else {
            map2SearchQuery = query
            searchTaskMap2?.cancel()
        }

        // Rule: Any search automatically disables camera lock
        if isLocked { isLocked = false }

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
            searchTaskMap1?.cancel()
            updateMap1Position(newPos, isUserGesture: true)
            map1SearchQuery = result.displayName
            map1SearchResults = []
            map1IsSearching = false
        } else {
            searchTaskMap2?.cancel()
            updateMap2Position(newPos, isUserGesture: true)
            map2SearchQuery = result.displayName
            map2SearchResults = []
            map2IsSearching = false
        }
    }

    // MARK: - Geocoding Service Implementation
    private func searchLocationService(query: String) async -> [SearchResultItem] {
        // 1. Try Apple Native MKGeocodingRequest (MapKit)
        if let geocoderResults = try? await geocodeWithMapKit(query: query), !geocoderResults.isEmpty {
            return geocoderResults
        }

        // 2. Fallback to OpenStreetMap Nominatim REST API
        return await geocodeWithNominatim(query: query)
    }

    private func geocodeWithMapKit(query: String) async throws -> [SearchResultItem] {
        guard let request = MKGeocodingRequest(addressString: query) else {
            return []
        }
        let mapItems = try await request.mapItems
        return mapItems.map { item in
            let coord = item.location.coordinate
            let formattedAddress = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
                ?? item.address?.fullAddress
            let parts = [item.name, formattedAddress]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let displayName: String
            if let name = item.name, let addr = formattedAddress, addr.hasPrefix(name) {
                displayName = addr
            } else if !parts.isEmpty {
                displayName = parts.joined(separator: ", ")
            } else {
                displayName = query
            }
            return SearchResultItem(
                displayName: displayName,
                latitude: coord.latitude,
                longitude: coord.longitude
            )
        }
    }

    private func geocodeWithNominatim(query: String) async -> [SearchResultItem] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://nominatim.openstreetmap.org/search?format=json&q=\(encoded)&limit=5") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("i2View/1.0 (iOS Map Viewer)", forHTTPHeaderField: "User-Agent")

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
}
