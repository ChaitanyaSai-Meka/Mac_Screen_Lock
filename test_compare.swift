import Foundation
let current = "1.0.2"
let remote = "1.0.1"
if remote.compare(current, options: .numeric) == .orderedDescending {
    print("Update available!")
} else {
    print("Up to date")
}
