import Foundation
import IOKit.ps

guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
      let firstSource = list.first,
      let info = IOPSGetPowerSourceDescription(blob, firstSource)?.takeUnretainedValue() as? [String: Any] else {
    print("Fail")
    exit(1)
}

print(info[kIOPSCurrentCapacityKey] as? Int ?? -1)
