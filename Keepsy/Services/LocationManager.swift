import Foundation
import CoreLocation
import Combine
@preconcurrency import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    // Lazy geocoder marked as deprecated to avoid warnings in newer iOS versions
    @available(iOS, deprecated: 26.0)
    private lazy var geocoder: CLGeocoder? = CLGeocoder()
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentCity: String = "NAPLES"
    @Published var isInNaples: Bool = true
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.authorizationStatus = manager.authorizationStatus
        
        // Request authorization if not determined
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.startUpdatingLocation()
        }
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
        
        // Stop updating location to save battery once we have it
        manager.stopUpdatingLocation()
        
        if #available(iOS 26.0, *) {
            Task {
                if let city = await reverseGeocode(location: location) {
                    let upperCity = city.uppercased()
                    self.currentCity = upperCity
                    self.isInNaples = (upperCity == "NAPLES" || upperCity == "NAPOLI")
                }
            }
        } else {
            performLegacyGeocoding(location: location)
        }
    }
    
    nonisolated private func reverseGeocode(location: CLLocation) async -> String? {
        if #available(iOS 26.0, *) {
            if let request = MKReverseGeocodingRequest(location: location) {
                do {
                    let mapItems = try await request.mapItems
                    return mapItems.first?.addressRepresentations?.cityName
                } catch {
                    return nil
                }
            }
        }
        return nil
    }
    
    @available(iOS, deprecated: 26.0)
    private func performLegacyGeocoding(location: CLLocation) {
        geocoder?.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let placemark = placemarks?.first, let city = placemark.locality {
                DispatchQueue.main.async {
                    let upperCity = city.uppercased()
                    self.currentCity = upperCity
                    self.isInNaples = (upperCity == "NAPLES" || upperCity == "NAPOLI")
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
    }
}
