import MapLibre

/// MapLibre 6.31 sorts every visible annotation again for each accessibility
/// index. Keep the same native annotation views and nearest-first order, but
/// calculate that order once per camera/data snapshot. Nothing is capped or hidden.
@MainActor
final class FieldMapView: MLNMapView {
    private struct Camera: Equatable {
        let latitude: Double, longitude: Double, zoom: Double, direction: Double, pitch: Double
        let bounds: CGRect
        let inset: UIEdgeInsets
        let location: Bool
        let locationView: ObjectIdentifier?
        let revision: Int
    }
    private struct AnnotationElements {
        let camera: Camera
        let start: Int
        let views: [MLNAnnotationView]
        let indices: [ObjectIdentifier: Int]
    }
    private var annotationRevision = 0
    private var annotationElements: AnnotationElements?

    func invalidateAnnotationAccessibility() {
        annotationRevision &+= 1
        annotationElements = nil
    }
    override func addAnnotation(_ annotation: MLNAnnotation) {
        invalidateAnnotationAccessibility(); super.addAnnotation(annotation)
    }
    override func addAnnotations(_ annotations: [MLNAnnotation]) {
        invalidateAnnotationAccessibility(); super.addAnnotations(annotations)
    }
    override func removeAnnotation(_ annotation: MLNAnnotation) {
        invalidateAnnotationAccessibility(); super.removeAnnotation(annotation)
    }
    override func removeAnnotations(_ annotations: [MLNAnnotation]) {
        invalidateAnnotationAccessibility(); super.removeAnnotations(annotations)
    }
    private func orderedAnnotations() -> AnnotationElements? {
        guard selectedAnnotations.isEmpty, userTrackingMode == .none else { return nil }
        // A GPS coordinate changes the native location element, not the order
        // of fixed field markers. Its view identity covers appearance/removal
        // of the SDK's optional prefix without invalidating on every GPS fix.
        let locationView = userLocation.flatMap { view(for: $0) }
        let camera = Camera(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude,
                            zoom: zoomLevel, direction: direction, pitch: self.camera.pitch,
                            bounds: bounds, inset: contentInset, location: showsUserLocation,
                            locationView: locationView.map(ObjectIdentifier.init), revision: annotationRevision)
        if let cached = annotationElements, cached.camera == camera { return cached }
        annotationElements = nil
        let annotations = visibleAnnotations ?? []
        // Leave ordinary maps and any SDK-managed non-view annotations alone.
        guard annotations.count > 100 else { return nil }
        let content = bounds.inset(by: contentInset)
        let center = CGPoint(x: content.midX, y: content.midY)
        var ranked: [(view: MLNAnnotationView, distance: CGFloat, ordinal: Int)] = []
        ranked.reserveCapacity(annotations.count)
        for (ordinal, annotation) in annotations.enumerated() {
            guard let view = view(for: annotation), view.superview != nil else { return nil }
            let point = convert(annotation.coordinate, toPointTo: self)
            ranked.append((view, hypot(point.x-center.x, point.y-center.y), ordinal))
        }
        ranked.sort { $0.distance == $1.distance ? $0.ordinal < $1.ordinal : $0.distance < $1.distance }
        let total = super.accessibilityElementCount()
        // The public view-for-annotation API returns the same native user view
        // the SDK counts before its field annotations. No per-index sort probe.
        let start = locationView == nil ? 1 : 2
        guard start + ranked.count <= total else { return nil }
        let views = ranked.map(\.view)
        var indices: [ObjectIdentifier: Int] = [:]
        for (index, view) in views.enumerated() { indices[ObjectIdentifier(view)] = start + index }
        let result = AnnotationElements(camera: camera, start: start, views: views, indices: indices)
        annotationElements = result
        return result
    }
    override func accessibilityElement(at index: Int) -> Any? {
        if let ordered = orderedAnnotations(), index >= ordered.start, index < ordered.start + ordered.views.count {
            return ordered.views[index - ordered.start]
        }
        // Preserve native location, compass, basemap features and attribution.
        return super.accessibilityElement(at: index)
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        if let ordered = orderedAnnotations(), let index = ordered.indices[ObjectIdentifier(element as AnyObject)] {
            return index
        }
        return super.index(ofAccessibilityElement: element)
    }
}
