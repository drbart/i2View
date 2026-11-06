import Foundation
import CoreLocation
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D) -> Void)?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var lastKnownCoordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocation(completion: @escaping (CLLocationCoordinate2D) -> Void) {
        self.completion = completion
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        #if os(iOS) || os(visionOS)
        case .authorizedWhenInUse, .authorizedAlways:
            if let location = manager.location {
                completion(location.coordinate)
                self.completion = nil
            } else {
                manager.requestLocation()
            }
        #elseif os(macOS)
        case .authorizedAlways:
            if let location = manager.location {
                completion(location.coordinate)
                self.completion = nil
            } else {
                manager.requestLocation()
            }
        #endif
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        #if os(iOS) || os(visionOS)
        let isAuthorized = (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways)
        #else
        let isAuthorized = (authorizationStatus == .authorizedAlways)
        #endif
        if isAuthorized, completion != nil {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastKnownCoordinate = location.coordinate
        completion?(location.coordinate)
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion = nil
    }
}
