import SwiftUI
import MapKit

// MARK: - Apple Maps View (MKMapView Representable)

struct AppleMapsView: UIViewRepresentable {
    var position: MapPosition
    var onPositionChanged: (MapPosition, Bool) -> Void

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator(onPositionChanged: onPositionChanged)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        context.coordinator.setupGestureRecognizers(on: mapView)
        context.coordinator.applyPosition(position, to: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.onPositionChanged = onPositionChanged
        if !context.coordinator.isUserInteracting {
            context.coordinator.applyPosition(position, to: uiView, animated: false)
        }
    }
}

// MARK: - OpenStreetMap Tile View (MKMapView + MKTileOverlay)

final class OSMTileOverlay: MKTileOverlay {
    init() {
        super.init(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        self.canReplaceMapContent = true
        self.maximumZ = 19
        self.minimumZ = 2
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = self.url(forTilePath: path)
        var request = URLRequest(url: url)
        request.setValue("i2View/1.0 (iOS Dual Map Comparison App)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            result(data, error)
        }.resume()
    }
}

struct OpenStreetMapTileView: UIViewRepresentable {
    var position: MapPosition
    var onPositionChanged: (MapPosition, Bool) -> Void

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator(onPositionChanged: onPositionChanged)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false

        let overlay = OSMTileOverlay()
        mapView.addOverlay(overlay, level: .aboveLabels)

        context.coordinator.setupGestureRecognizers(on: mapView)
        context.coordinator.applyPosition(position, to: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.onPositionChanged = onPositionChanged
        if !context.coordinator.isUserInteracting {
            context.coordinator.applyPosition(position, to: uiView, animated: false)
        }
    }
}

// MARK: - Shared MKMapView Coordinator

final class MapCoordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    var onPositionChanged: (MapPosition, Bool) -> Void
    var isUserInteracting: Bool = false
    private var isProgrammaticUpdate: Bool = false
    private var lastAppliedPosition: MapPosition?

    init(onPositionChanged: @escaping (MapPosition, Bool) -> Void) {
        self.onPositionChanged = onPositionChanged
    }

    func setupGestureRecognizers(on mapView: MKMapView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        pan.delegate = self
        mapView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        pinch.delegate = self
        mapView.addGestureRecognizer(pinch)

        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleGesture(_:)))
        rotation.delegate = self
        mapView.addGestureRecognizer(rotation)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        mapView.addGestureRecognizer(doubleTap)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleGesture(_ recognizer: UIGestureRecognizer) {
        guard let mapView = recognizer.view as? MKMapView else { return }
        switch recognizer.state {
        case .began:
            isUserInteracting = true
        case .changed:
            isUserInteracting = true
            reportCurrentRegion(from: mapView, isUser: true)
        case .ended, .cancelled, .failed:
            reportCurrentRegion(from: mapView, isUser: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.isUserInteracting = false
            }
        default:
            break
        }
    }

    @objc private func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            isUserInteracting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.isUserInteracting = false
            }
        }
    }

    func applyPosition(_ position: MapPosition, to mapView: MKMapView, animated: Bool) {
        if let last = lastAppliedPosition,
           abs(last.latitude - position.latitude) < 0.00001,
           abs(last.longitude - position.longitude) < 0.00001,
           abs(last.zoom - position.zoom) < 0.01 {
            return
        }

        let currentCenter = mapView.region.center
        let currentZoom = MapPosition.zoom(fromLongitudeDelta: mapView.region.span.longitudeDelta)
        if abs(currentCenter.latitude - position.latitude) < 0.00001,
           abs(currentCenter.longitude - position.longitude) < 0.00001,
           abs(currentZoom - position.zoom) < 0.02 {
            lastAppliedPosition = position
            return
        }

        isProgrammaticUpdate = true
        lastAppliedPosition = position

        let spanDelta = position.longitudeDelta
        let latDelta = min(spanDelta, 150.0)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: min(spanDelta, 350.0))
        let region = MKCoordinateRegion(center: position.coordinate, span: span)
        mapView.setRegion(region, animated: animated)

        DispatchQueue.main.async { [weak self] in
            self?.isProgrammaticUpdate = false
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        guard !isProgrammaticUpdate && isUserInteracting else { return }
        reportCurrentRegion(from: mapView, isUser: true)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard !isProgrammaticUpdate else { return }
        if isUserInteracting {
            reportCurrentRegion(from: mapView, isUser: true)
        }
    }

    private func reportCurrentRegion(from mapView: MKMapView, isUser: Bool) {
        let region = mapView.region
        let zoom = MapPosition.zoom(fromLongitudeDelta: region.span.longitudeDelta)
        let newPos = MapPosition(
            latitude: region.center.latitude.clamped(to: -85.0...85.0),
            longitude: region.center.longitude,
            zoom: zoom,
            pitch: Double(mapView.camera.pitch),
            heading: mapView.camera.heading
        )
        lastAppliedPosition = newPos
        onPositionChanged(newPos, isUser)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let tileOverlay = overlay as? MKTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
