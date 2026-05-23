import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    @Published var currentCity: String = "NAPLES"
    @Published var isInNaples: Bool = true
    
    enum SimCity: String, CaseIterable, Identifiable {
        case actual = "GPS REALE"
        case naples = "NAPLES"
        case rome = "ROME"
        case florence = "FLORENCE"
        
        var id: String { self.rawValue }
    }
    
    @Published var selectedSimCity: SimCity = .naples
    
    override init() {
        super.init()
    }
}
