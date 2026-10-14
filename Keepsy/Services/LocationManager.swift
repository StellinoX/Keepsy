import Foundation
import CoreLocation
import Observation
import UserNotifications
@preconcurrency import MapKit

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentCity: String = "NAPLES"
    var isInNaples: Bool = true
    var lastKnownLocation: CLLocation? = nil

    private var isHighAccuracyMode = false
    private var wasNearDeveloperCenter = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.authorizationStatus = manager.authorizationStatus
        self.lastKnownLocation = manager.location

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

    private func isNearDeveloperCenter() -> Bool {
        guard let userLoc = lastKnownLocation else { return false }
        // Apple Developer Academy in San Giovanni a Teduccio, Naples, Italy (500m range)
        let academyLoc = CLLocation(latitude: 40.8355, longitude: 14.3095)
        if userLoc.distance(from: academyLoc) <= 500.0 {
            return true
        }
        // User's House (small 15m range)
        let houseLoc = CLLocation(latitude: 40.923694, longitude: 14.321333)
        if userLoc.distance(from: houseLoc) <= 15.0 {
            return true
        }
        return false
    }

    func distanceTo(museum: Museum) -> CLLocationDistance? {
        guard let userLoc = lastKnownLocation else { return nil }
        if isNearDeveloperCenter() {
            return 0.0
        }
        let museumLoc = CLLocation(latitude: museum.latitude, longitude: museum.longitude)
        return userLoc.distance(from: museumLoc)
    }

    func isUserNear(museum: Museum) -> Bool {
        if isNearDeveloperCenter() {
            return true
        }
        guard let dist = distanceTo(museum: museum) else { return false }
        return dist <= museum.geofenceRadius
    }

    func closestMuseum(from museums: [Museum]) -> Museum? {
        guard let userLoc = lastKnownLocation else { return nil }
        return museums.min(by: { m1, m2 in
            let loc1 = CLLocation(latitude: m1.latitude, longitude: m1.longitude)
            let loc2 = CLLocation(latitude: m2.latitude, longitude: m2.longitude)
            return userLoc.distance(from: loc1) < userLoc.distance(from: loc2)
        })
    }

    func sortedMuseums(_ museums: [Museum]) -> [Museum] {
        guard let userLoc = lastKnownLocation else { return museums }
        return museums.sorted { m1, m2 in
            let loc1 = CLLocation(latitude: m1.latitude, longitude: m1.longitude)
            let loc2 = CLLocation(latitude: m2.latitude, longitude: m2.longitude)
            return userLoc.distance(from: loc1) < userLoc.distance(from: loc2)
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

        DispatchQueue.main.async {
            self.lastKnownLocation = location
            
            // Trigger local notification when entering Developer Center
            let currentlyNear = self.isNearDeveloperCenter()
            if currentlyNear && !self.wasNearDeveloperCenter {
                self.sendDeveloperCenterNotification()
            }
            self.wasNearDeveloperCenter = currentlyNear
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

    private func sendDeveloperCenterNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Welcome to the Developer Center of Keepsy"
            content.sound = UNNotificationSound.default
            
            let request = UNNotificationRequest(
                identifier: "DeveloperCenterEntrance",
                content: content,
                trigger: nil // immediate
            )
            center.add(request) { error in
                if let error = error {
                    print("Failed to post notification: \(error.localizedDescription)")
                }
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
