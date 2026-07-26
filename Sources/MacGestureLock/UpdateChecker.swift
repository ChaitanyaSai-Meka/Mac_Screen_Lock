import AppKit

struct GitHubRelease: Codable {
    let tagName: String
    let body: String?
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlUrl = "html_url"
    }
}

@MainActor
final class UpdateChecker {
    static let updateURL = URL(string: "https://api.github.com/repos/ChaitanyaSai-Meka/Mac_Screen_Lock/releases/latest")!
    
    static func check(manual: Bool) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        
        var request = URLRequest(url: updateURL)
        request.setValue("H0Ver-Mac-App", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                if manual {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not connect to the update server. Please check your internet connection."
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
                return
            }
            
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                
                let remoteVersion = release.tagName.replacingOccurrences(of: "v", with: "")
                
                DispatchQueue.main.async {
                    if remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                        showUpdateAlert(release: release, remoteVersion: remoteVersion)
                    } else if manual {
                        let alert = NSAlert()
                        alert.messageText = "You're up to date!"
                        alert.informativeText = "H0Ver \(currentVersion) is currently the newest version available."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            } catch {
                if manual {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "The update server returned an invalid response. (You may have hit GitHub's API rate limit)."
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }.resume()
    }
    
    private static func showUpdateAlert(release: GitHubRelease, remoteVersion: String) {
        let alert = NSAlert()
        alert.messageText = "A new version of H0Ver is available!"
        alert.informativeText = "Version \(remoteVersion) is available to download.\n\n" + (release.body ?? "")
        alert.alertStyle = .informational
        
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
