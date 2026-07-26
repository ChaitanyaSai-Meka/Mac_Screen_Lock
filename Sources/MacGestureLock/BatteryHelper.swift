import Foundation

struct BatteryStatus {
    var percentage: Int
    var isCharging: Bool
}

final class BatteryHelper {
    static func getStatus() -> BatteryStatus? {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "batt"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse percentage
                var percentage = 100
                if let range = output.range(of: #"(\d+)%"#, options: .regularExpression),
                   let percentStr = output[range].split(separator: "%").first,
                   let p = Int(percentStr) {
                    percentage = p
                }
                
                let isCharging = output.contains("AC Power") || output.contains("charging")
                return BatteryStatus(percentage: percentage, isCharging: isCharging)
            }
        } catch {
            return nil
        }
        return nil
    }
}
