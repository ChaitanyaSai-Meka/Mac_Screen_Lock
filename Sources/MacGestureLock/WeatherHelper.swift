import Foundation
import CoreLocation

struct WeatherStatus {
    let temperature: Double
    let weatherCode: Int
    let city: String
    
    var symbol: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "snowflake"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

@MainActor
final class WeatherHelper: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherHelper()
    
    private var isMonitoring = false
    private var timer: Timer?
    private(set) var currentStatus: WeatherStatus?
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        let authStatus = locationManager.authorizationStatus
        if authStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if authStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else {
            NSLog("WeatherHelper: Location access denied.")
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestLocationUpdate()
            }
        }
    }
    
    private func requestLocationUpdate() {
        let authStatus = locationManager.authorizationStatus
        if authStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            fetchWeather(for: location)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("WeatherHelper Location Error: \(error.localizedDescription)")
    }
    
    private func fetchWeather(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            let city = placemarks?.first?.locality ?? "Unknown City"
            
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude
            let weatherUrlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&temperature_unit=celsius"
            guard let weatherUrl = URL(string: weatherUrlStr) else { return }
            
            URLSession.shared.dataTask(with: weatherUrl) { wData, wResp, wErr in
                if let wErr = wErr {
                    NSLog("WeatherHelper Open-Meteo Fetch Error: \(wErr.localizedDescription)")
                    return
                }
                guard let wData = wData,
                      let wJson = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
                      let current = wJson["current"] as? [String: Any],
                      let temp = current["temperature_2m"] as? Double,
                      let code = current["weather_code"] as? Int else {
                    NSLog("WeatherHelper Open-Meteo Fetch Error: Invalid JSON or missing data.")
                    return
                }
                
                NSLog("WeatherHelper Open-Meteo Fetch Success: \(temp)°C, code \(code)")
                
                Task { @MainActor in
                    let status = WeatherStatus(temperature: temp, weatherCode: code, city: city)
                    self.currentStatus = status
                    NotificationCenter.default.post(name: NSNotification.Name("WeatherStatusChanged"), object: nil, userInfo: ["status": status])
                }
            }.resume()
        }
    }
}
