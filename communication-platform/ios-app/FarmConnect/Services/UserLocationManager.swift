import CoreLocation
import Foundation

@MainActor
final class UserLocationManager: NSObject, ObservableObject {
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var city: String?
    @Published var isLocating = false
    @Published var locationError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestCurrentLocation() {
        locationError = nil
        isLocating = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            isLocating = false
            locationError = "Location permission denied. Enable it in Settings."
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        @unknown default:
            isLocating = false
            locationError = "Unable to access location."
        }
    }
}

extension UserLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let loc = locations.last else {
                isLocating = false
                locationError = "Could not determine location."
                return
            }
            latitude = loc.coordinate.latitude
            longitude = loc.coordinate.longitude

            geocoder.reverseGeocodeLocation(loc) { placemarks, _ in
                Task { @MainActor in
                    self.isLocating = false
                    if let place = placemarks?.first {
                        self.city = place.locality ?? place.administrativeArea ?? "Unknown"
                    } else {
                        self.city = "Unknown"
                    }
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isLocating = false
            locationError = "Location error: \(error.localizedDescription)"
        }
    }
}
