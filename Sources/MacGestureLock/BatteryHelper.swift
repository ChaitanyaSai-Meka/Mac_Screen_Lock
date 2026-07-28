import Foundation
import IOKit.ps

struct BatteryStatus {
    var percentage: Int
    var isPluggedIn: Bool
}

final class BatteryHelper {
    static func getStatus() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = list.first,
              let info = IOPSGetPowerSourceDescription(blob, firstSource)?.takeUnretainedValue() as? [String: Any] else {
            return nil
        }
        
        let percentage = info[kIOPSCurrentCapacityKey] as? Int ?? 100
        
        // A Mac can be plugged in but not actively "charging" (e.g., Optimized Battery Charging)
        // Checking for "AC Power" is more reliable for showing the plugged-in icon.
        let state = info[kIOPSPowerSourceStateKey] as? String ?? ""
        let isPluggedIn = (state == kIOPSACPowerValue)
        
        return BatteryStatus(percentage: percentage, isPluggedIn: isPluggedIn)
    }
    
    static func startMonitoring() {
        let callback: IOPowerSourceCallbackType = { _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("BatteryStatusChanged"), object: nil)
            }
        }
        if let loopSource = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        }
    }
}
