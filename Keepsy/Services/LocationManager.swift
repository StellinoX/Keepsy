import Foundation
import CoreLocation
import Observation
@preconcurrency import MapKit

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentCity: String = "NAPLES"
    var isInNaples: Bool = true
    var lastKnownLocation: CLLocation? = nil

    private var isHighAccuracyMode = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.authorizationStatus = manager.authorizationStatus

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.startUpdatingLocation()
        }
    }

    func startHighAccuracyTracking() {
        isHighAccuracyMode = true
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isHighAccuracyMode = false
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.stopUpdatingLocation()
    }

    func distanceTo(museum: Museum) -> CLLocationDistance? {
        guard let userLoc = lastKnownLocation else { return nil }
        let museumLoc = CLLocation(latitude: museum.latitude, longitude: museum.longitude)
        return userLoc.distance(from: museumLoc)
    }

    func isUserNear(museum: Museum) -> Bool {
        guard let dist = distanceTo(museum: museum) else { return false }
        return dist <= museum.geofenceRadius
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        DispatchQueue.main.async {
            self.lastKnownLocation = location
        }

        if !isHighAccuracyMode {
            manager.stopUpdatingLocation()
        }

        Task {
            if let city = await reverseGeocode(location: location) {
                let upperCity = city.uppercased()
                self.currentCity = upperCity
                self.isInNaples = (upperCity == "NAPLES" || upperCity == "NAPOLI")
            }
        }
    }

    nonisolated private func reverseGeocode(location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            return mapItems.first?.addressRepresentations?.cityName
        } catch {
            return nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
    }
}
