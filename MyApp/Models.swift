import Foundation
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

    /// Converts zoom level (2..20) to approximate MKCoordinateSpan longitudeDelta
    var longitudeDelta: Double {
        let clampedZoom = zoom.clamped(to: 2.0...20.0)
        return 360.0 / pow(2.0, clampedZoom)
    }

    /// Computes approximate zoom level (2..20) from MKCoordinateSpan longitudeDelta
    static func zoom(fromLongitudeDelta delta: Double) -> Double {
        guard delta > 0 else { return 12.0 }
        let zoom = log2(360.0 / delta)
        return zoom.clamped(to: 2.0...20.0)
    }
}

struct SearchResultItem: Identifiable, Equatable {
    let id = UUID()
    let displayName: String
    let latitude: Double
    let longitude: Double
}

enum MapEngine: String, CaseIterable {
    case appleMaps
    case openStreetMap
}

enum SyncMode: String, CaseIterable {
    case exact
    case relative
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
