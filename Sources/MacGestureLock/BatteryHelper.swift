import Foundation
import IOKit.ps

struct BatteryStatus {
    var percentage: Int
    var isCharging: Bool
}

final class BatteryHelper {
    static func getStatus() -> BatteryStatus? {
        // Fetch power sources from the macOS kernel directly (0 CPU cost)
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = list.first,
              let info = IOPSGetPowerSourceDescription(blob, firstSource)?.takeUnretainedValue() as? [String: Any] else {
            return nil
        }
        
        let percentage = info[kIOPSCurrentCapacityKey] as? Int ?? 100
        let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
        
        return BatteryStatus(percentage: percentage, isCharging: isCharging)
    }
}
