import CoreLocation
@preconcurrency import MapLibre
import OSLog
import SwiftUI
import UIKit

enum ActivityMapLayerID {
    static let source = "gonow-activities"
    static let clusterHalo = "gonow-cluster-halo"
    static let clusters = "gonow-clusters"
    static let clusterCount = "gonow-cluster-count"
    static let selectedHalo = "gonow-selected-activity-halo"
    static let activities = "gonow-activity-markers"
    static let userSource = "gonow-user-location"
    static let userHalo = "gonow-user-location-halo"
    static let userPoint = "gonow-user-location-point"
    static let markerImage = "gonow-map-point"
    static let selectedMarkerImage = "gonow-map-point-selected"
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
        private var activityFingerprint = ""
        private var userFingerprint = ""
        private var isStyleReady = false
        private var hasRenderedMap = false

        init(parent: MapLibreActivityMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            configure(style: style)
            isStyleReady = true
            activityFingerprint = ""
            userFingerprint = ""
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
            let nextActivityFingerprint = parent.activities
                .map {
                    [
                        $0.id,
                        String($0.coordinate.latitude),
                        String($0.coordinate.longitude),
                        $0.title,
                        $0.category.rawValue,
                        String($0.participantCount),
                        $0.participantLimit.map(String.init) ?? "none",
                        String($0.isFull),
                    ].joined(separator: ":")
                }
                .joined(separator: "|") + "#\(parent.selectedActivityID ?? "")"
            if activityFingerprint != nextActivityFingerprint,
               let source = style.source(withIdentifier: ActivityMapLayerID.source) as? MLNShapeSource {
                source.shape = activityShape()
                activityFingerprint = nextActivityFingerprint
            }

            let nextUserFingerprint = parent.userCoordinate.map { "\($0.latitude):\($0.longitude)" } ?? "none"
            if userFingerprint != nextUserFingerprint,
               let source = style.source(withIdentifier: ActivityMapLayerID.userSource) as? MLNShapeSource {
                source.shape = parent.userCoordinate.map(userLocationShape)
                userFingerprint = nextUserFingerprint
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
            let layerIDs: Set<String> = [
                ActivityMapLayerID.clusters,
                ActivityMapLayerID.clusterCount,
                ActivityMapLayerID.activities,
            ]
            let hitArea = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let features = mapView.visibleFeatures(in: hitArea, styleLayerIdentifiers: layerIDs)
            if let cluster = features.compactMap({ $0 as? MLNPointFeatureCluster }).first,
               let source = mapView.style?.source(withIdentifier: ActivityMapLayerID.source) as? MLNShapeSource {
                let zoom = source.zoomLevel(forExpanding: cluster)
                mapView.setCenter(cluster.coordinate, zoomLevel: zoom, animated: !parent.reduceMotion)
                return
            }
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
            style.setImage(markerImage(color: UIColor.systemPink, pointSize: 36), forName: ActivityMapLayerID.markerImage)
            style.setImage(markerImage(color: UIColor.systemPurple, pointSize: 42), forName: ActivityMapLayerID.selectedMarkerImage)

            let activitySource = MLNShapeSource(
                identifier: ActivityMapLayerID.source,
                shape: activityShape(),
                options: [
                    .clustered: true,
                    .clusterRadius: 58,
                    .maximumZoomLevelForClustering: 14,
                ]
            )
            style.addSource(activitySource)

            let clusterHalo = MLNCircleStyleLayer(identifier: ActivityMapLayerID.clusterHalo, source: activitySource)
            clusterHalo.predicate = NSPredicate(format: "cluster == YES")
            clusterHalo.circleColor = NSExpression(forConstantValue: UIColor.systemPink.withAlphaComponent(0.16))
            clusterHalo.circleRadius = NSExpression(forConstantValue: 30)
            clusterHalo.circleBlur = NSExpression(forConstantValue: 0.4)
            style.addLayer(clusterHalo)

            let clusters = MLNCircleStyleLayer(identifier: ActivityMapLayerID.clusters, source: activitySource)
            clusters.predicate = NSPredicate(format: "cluster == YES")
            clusters.circleColor = NSExpression(forConstantValue: UIColor.systemPink)
            clusters.circleRadius = NSExpression(forConstantValue: 22)
            clusters.circleStrokeColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.9))
            clusters.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            style.addLayer(clusters)

            let count = MLNSymbolStyleLayer(identifier: ActivityMapLayerID.clusterCount, source: activitySource)
            count.predicate = NSPredicate(format: "cluster == YES")
            count.text = NSExpression(forKeyPath: "point_count_abbreviated")
            count.textColor = NSExpression(forConstantValue: UIColor.white)
            count.textFontSize = NSExpression(forConstantValue: 12)
            count.textAllowsOverlap = NSExpression(forConstantValue: true)
            style.addLayer(count)

            let selectedHalo = MLNCircleStyleLayer(identifier: ActivityMapLayerID.selectedHalo, source: activitySource)
            selectedHalo.predicate = NSPredicate(format: "cluster != YES AND is_selected == YES")
            selectedHalo.circleColor = NSExpression(forConstantValue: UIColor.systemPink.withAlphaComponent(0.2))
            selectedHalo.circleRadius = NSExpression(forConstantValue: 27)
            selectedHalo.circleBlur = NSExpression(forConstantValue: 0.45)
            style.addLayer(selectedHalo)

            let markers = MLNSymbolStyleLayer(identifier: ActivityMapLayerID.activities, source: activitySource)
            markers.predicate = NSPredicate(format: "cluster != YES")
            markers.iconImageName = NSExpression(forKeyPath: "marker_image")
            markers.iconAllowsOverlap = NSExpression(forConstantValue: true)
            markers.iconScale = NSExpression(forConstantValue: 1)
            style.addLayer(markers)

            let userSource = MLNShapeSource(identifier: ActivityMapLayerID.userSource, shape: nil, options: nil)
            style.addSource(userSource)
            let userHalo = MLNCircleStyleLayer(identifier: ActivityMapLayerID.userHalo, source: userSource)
            userHalo.circleColor = NSExpression(forConstantValue: UIColor.systemBlue.withAlphaComponent(0.18))
            userHalo.circleRadius = NSExpression(forConstantValue: 18)
            userHalo.circleBlur = NSExpression(forConstantValue: 0.45)
            style.addLayer(userHalo)
            let userPoint = MLNCircleStyleLayer(identifier: ActivityMapLayerID.userPoint, source: userSource)
            userPoint.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
            userPoint.circleRadius = NSExpression(forConstantValue: 7)
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
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            return UIImage(systemName: "mappin.circle.fill", withConfiguration: configuration)?
                .withTintColor(color, renderingMode: .alwaysOriginal) ?? UIImage()
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
