import CoreLocation
@preconcurrency import MapLibre
import OSLog
import SwiftUI
import UIKit

enum ActivityMapLayerID {
    static let source = "gonow-activities"
    static let selectedHalo = "gonow-selected-activity-halo"
    static let activities = "gonow-activity-markers"
    static let userSource = "gonow-user-location"
    static let userHalo = "gonow-user-location-halo"
    static let userPoint = "gonow-user-location-point"
}

struct MapLibreCameraCommand: Equatable {
    let id = UUID()
    let coordinate: MapCoordinate
    let zoom: Double
}

enum MapLibreLoadState: Equatable {
    case loading
    case loaded
    case failed
}

struct MapLibreActivityMap: UIViewRepresentable {
    private static let bootstrapStyleJSON = """
    {
      "version": 8,
      "name": "GoNow Bootstrap",
      "sources": {},
      "layers": [
        {
          "id": "gonow-bootstrap-background",
          "type": "background",
          "paint": { "background-color": "#F6F5FA" }
        }
      ]
    }
    """

    let styleJSON: String
    let activities: [MapActivity]
    let userCoordinate: MapCoordinate?
    let selectedActivityID: String?
    let initialCamera: PersistedMapCamera
    let cameraCommand: MapLibreCameraCommand?
    let reduceMotion: Bool
    let onLoadStateChange: (MapLibreLoadState) -> Void
    let onViewportIdle: (MapViewport, Double, Double) -> Void
    let onSelectActivity: (String) -> Void
    let onDeselectActivity: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MLNMapView {
        // Install the delegate before loading the real style. A local style may finish
        // synchronously, so passing it to the initializer can lose the ready callback.
        let mapView = MLNMapView(frame: .zero, styleJSON: Self.bootstrapStyleJSON)
        mapView.delegate = context.coordinator
        mapView.tintColor = UIColor(AppColors.accentPrimary)
        mapView.compassView.isHidden = true
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        let startingCoordinate = cameraCommand?.coordinate ?? initialCamera.center
        let startingZoom = cameraCommand?.zoom ?? initialCamera.zoom
        mapView.setCenter(
            startingCoordinate.coreLocationCoordinate,
            zoomLevel: startingZoom,
            direction: cameraCommand == nil ? initialCamera.bearing : 0,
            animated: false
        )
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTapMap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)
        context.coordinator.mapView = mapView
        context.coordinator.lastCameraCommandID = cameraCommand?.id
        mapView.styleJSON = styleJSON
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateSources(in: mapView)
        if let command = cameraCommand, context.coordinator.lastCameraCommandID != command.id {
            context.coordinator.lastCameraCommandID = command.id
            mapView.setCenter(
                command.coordinate.coreLocationCoordinate,
                zoomLevel: command.zoom,
                animated: !reduceMotion
            )
        }
        if let selectedActivityID,
           context.coordinator.lastSelectedActivityID != selectedActivityID,
           let activity = activities.first(where: { $0.id == selectedActivityID }) {
            context.coordinator.lastSelectedActivityID = selectedActivityID
            mapView.setCenter(activity.coordinate.coreLocationCoordinate, animated: !reduceMotion)
        } else if selectedActivityID == nil {
            context.coordinator.lastSelectedActivityID = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate, UIGestureRecognizerDelegate {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "GoNow",
            category: "MapLibre"
        )

        var parent: MapLibreActivityMap
        weak var mapView: MLNMapView?
        var lastCameraCommandID: UUID?
        var lastSelectedActivityID: String?
        private var renderedActivities: [MapActivity] = []
        private var renderedSelectedActivityID: String?
        private var renderedUserCoordinate: MapCoordinate?
        private var isStyleReady = false
        private var hasRenderedMap = false

        init(parent: MapLibreActivityMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            configure(style: style)
            isStyleReady = true
            renderedActivities = []
            renderedSelectedActivityID = nil
            renderedUserCoordinate = nil
            updateSources(in: mapView)
            notifyViewportChanged(mapView)
        }

        func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard isStyleReady else { return }
            markMapUsable()
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            if hasRenderedMap {
                Self.logger.warning(
                    "Map resource failed after the style became usable: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            Self.logger.error("MapLibre failed to load the map: \(error.localizedDescription, privacy: .public)")
            parent.onLoadStateChange(.failed)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard isStyleReady else { return }
            notifyViewportChanged(mapView)
        }

        func updateSources(in mapView: MLNMapView) {
            guard isStyleReady, let style = mapView.style else { return }
            if renderedActivities != parent.activities || renderedSelectedActivityID != parent.selectedActivityID,
               let source = style.source(withIdentifier: ActivityMapLayerID.source) as? MLNShapeSource {
                source.shape = activityShape()
                renderedActivities = parent.activities
                renderedSelectedActivityID = parent.selectedActivityID
            }

            if renderedUserCoordinate != parent.userCoordinate,
               let source = style.source(withIdentifier: ActivityMapLayerID.userSource) as? MLNShapeSource {
                source.shape = parent.userCoordinate.map(userLocationShape)
                renderedUserCoordinate = parent.userCoordinate
            }
        }

        private func markMapUsable() {
            guard !hasRenderedMap else { return }
            hasRenderedMap = true
            parent.onLoadStateChange(.loaded)
        }

        @objc func didTapMap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let mapView else { return }
            let point = recognizer.location(in: mapView)
            let layerIDs: Set<String> = [ActivityMapLayerID.activities]
            let hitArea = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let features = mapView.visibleFeatures(in: hitArea, styleLayerIdentifiers: layerIDs)
            if let activityID = features
                .compactMap({ $0.attribute(forKey: "activity_id") as? String })
                .first {
                parent.onSelectActivity(activityID)
                return
            }
            parent.onDeselectActivity()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func configure(style: MLNStyle) {
            for category in ActivityCategory.allCases {
                let color = markerColor(for: category)
                style.setImage(
                    markerImage(color: color, pointSize: 38),
                    forName: category.markerImageName(isSelected: false)
                )
                style.setImage(
                    markerImage(color: color, pointSize: 46),
                    forName: category.markerImageName(isSelected: true)
                )
            }

            let activitySource = MLNShapeSource(
                identifier: ActivityMapLayerID.source,
                shape: activityShape(),
                options: nil
            )
            style.addSource(activitySource)

            let selectedHalo = MLNCircleStyleLayer(identifier: ActivityMapLayerID.selectedHalo, source: activitySource)
            selectedHalo.predicate = NSPredicate(format: "is_selected == YES")
            selectedHalo.circleColor = NSExpression(forConstantValue: UIColor.systemPink.withAlphaComponent(0.2))
            selectedHalo.circleRadius = NSExpression(forConstantValue: 27)
            selectedHalo.circleBlur = NSExpression(forConstantValue: 0.45)
            selectedHalo.minimumZoomLevel = 0
            selectedHalo.maximumZoomLevel = 24
            style.addLayer(selectedHalo)

            let markers = MLNSymbolStyleLayer(identifier: ActivityMapLayerID.activities, source: activitySource)
            markers.iconImageName = NSExpression(forKeyPath: "marker_image")
            markers.iconAllowsOverlap = NSExpression(forConstantValue: true)
            markers.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            markers.iconAnchor = NSExpression(forConstantValue: "bottom")
            markers.iconScale = NSExpression(forConstantValue: 1)
            markers.minimumZoomLevel = 0
            markers.maximumZoomLevel = 24
            style.addLayer(markers)

            let userSource = MLNShapeSource(identifier: ActivityMapLayerID.userSource, shape: nil, options: nil)
            style.addSource(userSource)
            let userHalo = MLNCircleStyleLayer(identifier: ActivityMapLayerID.userHalo, source: userSource)
            userHalo.circleColor = NSExpression(forConstantValue: UIColor.systemRed.withAlphaComponent(0.2))
            userHalo.circleRadius = NSExpression(forConstantValue: 20)
            userHalo.circleBlur = NSExpression(forConstantValue: 0.45)
            style.addLayer(userHalo)
            let userPoint = MLNCircleStyleLayer(identifier: ActivityMapLayerID.userPoint, source: userSource)
            userPoint.circleColor = NSExpression(forConstantValue: UIColor.systemRed)
            userPoint.circleRadius = NSExpression(forConstantValue: 8)
            userPoint.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            userPoint.circleStrokeWidth = NSExpression(forConstantValue: 3)
            style.addLayer(userPoint)
        }

        private func activityShape() -> MLNShapeCollectionFeature {
            let features = parent.activities.map { activity -> MLNPointFeature in
                let properties = activity.renderProperties(isSelected: activity.id == parent.selectedActivityID)
                let feature = MLNPointFeature()
                feature.coordinate = activity.coordinate.coreLocationCoordinate
                feature.identifier = activity.id as NSString
                var attributes: [String: Any] = [
                    "activity_id": properties.activityID,
                    "category": properties.category,
                    "title": properties.title,
                    "participants_count": properties.participantCount,
                    "is_full": properties.isFull,
                    "is_selected": properties.isSelected,
                    "marker_image": properties.markerImage,
                ]
                if let limit = properties.participantLimit {
                    attributes["participants_limit"] = limit
                }
                feature.attributes = attributes
                return feature
            }
            return MLNShapeCollectionFeature(shapes: features)
        }

        private func userLocationShape(_ coordinate: MapCoordinate) -> MLNPointFeature {
            let feature = MLNPointFeature()
            feature.coordinate = coordinate.coreLocationCoordinate
            return feature
        }

        private func markerImage(color: UIColor, pointSize: CGFloat) -> UIImage {
            let size = CGSize(width: pointSize, height: pointSize * 1.28)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let width = size.width
                let height = size.height
                let centerX = width / 2
                let tip = CGPoint(x: centerX, y: height - 1)
                let pin = UIBezierPath()
                pin.move(to: tip)
                pin.addCurve(
                    to: CGPoint(x: 1, y: height * 0.38),
                    controlPoint1: CGPoint(x: centerX - width * 0.12, y: height * 0.76),
                    controlPoint2: CGPoint(x: 1, y: height * 0.61)
                )
                pin.addCurve(
                    to: CGPoint(x: centerX, y: 1),
                    controlPoint1: CGPoint(x: 1, y: height * 0.14),
                    controlPoint2: CGPoint(x: width * 0.24, y: 1)
                )
                pin.addCurve(
                    to: CGPoint(x: width - 1, y: height * 0.38),
                    controlPoint1: CGPoint(x: width * 0.76, y: 1),
                    controlPoint2: CGPoint(x: width - 1, y: height * 0.14)
                )
                pin.addCurve(
                    to: tip,
                    controlPoint1: CGPoint(x: width - 1, y: height * 0.61),
                    controlPoint2: CGPoint(x: centerX + width * 0.12, y: height * 0.76)
                )
                pin.close()

                context.cgContext.setShadow(
                    offset: CGSize(width: 0, height: 2),
                    blur: 3,
                    color: UIColor.black.withAlphaComponent(0.2).cgColor
                )
                color.setFill()
                pin.fill()
                context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

                let centerRadius = width * 0.13
                let center = CGRect(
                    x: centerX - centerRadius,
                    y: height * 0.31 - centerRadius,
                    width: centerRadius * 2,
                    height: centerRadius * 2
                )
                UIColor.white.setFill()
                UIBezierPath(ovalIn: center).fill()
            }.withRenderingMode(.alwaysOriginal)
        }

        private func markerColor(for category: ActivityCategory) -> UIColor {
            switch category {
            case .walking: .systemGreen
            case .sport: .systemRed
            case .travel: .systemBlue
            case .music: .systemPurple
            case .games: .systemIndigo
            case .food: .systemOrange
            case .help: .systemTeal
            case .education: .systemBrown
            case .animals: .systemMint
            case .event: .systemPink
            case .other: .systemGray
            }
        }

        private func notifyViewportChanged(_ mapView: MLNMapView) {
            let bounds = mapView.visibleCoordinateBounds
            parent.onViewportIdle(
                MapViewport(
                    bounds: MapBounds(
                        south: bounds.sw.latitude,
                        west: bounds.sw.longitude,
                        north: bounds.ne.latitude,
                        east: bounds.ne.longitude
                    ),
                    center: MapCoordinate(mapView.centerCoordinate),
                    zoom: mapView.zoomLevel
                ),
                mapView.direction,
                mapView.camera.pitch
            )
        }
    }
}

extension MapCoordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coreLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
