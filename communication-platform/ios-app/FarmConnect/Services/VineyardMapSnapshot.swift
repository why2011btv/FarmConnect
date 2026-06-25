import MapKit
import UIKit

/// Captures a satellite snapshot of a map region as a JPEG data URL, for the backend's
/// vision-based vine-boundary fallback. Needs no location permission.
enum VineyardMapSnapshot {
    /// Returns a `data:image/jpeg;base64,...` URL string, or nil on failure (best-effort).
    static func make(region: MKCoordinateRegion, size: CGSize = CGSize(width: 600, height: 600)) async -> VineyardAnalyzeRequest.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.mapType = .satellite
        options.size = size
        options.scale = 1

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            guard let data = snapshot.image.jpegData(compressionQuality: 0.6) else { return nil }
            let dataUrl = "data:image/jpeg;base64,\(data.base64EncodedString())"
            return VineyardAnalyzeRequest.Snapshot(
                imageDataUrl: dataUrl,
                region: VineyardAnalyzeRequest.Region(
                    centerLat: region.center.latitude,
                    centerLng: region.center.longitude,
                    latDelta: region.span.latitudeDelta,
                    lngDelta: region.span.longitudeDelta
                )
            )
        } catch {
            return nil
        }
    }
}
