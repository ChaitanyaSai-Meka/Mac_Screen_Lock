import Foundation

struct MediaStatus {
    let title: String
    let artist: String
    let isPlaying: Bool
}

@MainActor
final class MediaHelper {
    static let shared = MediaHelper()
    
    private var isMonitoring = false
    private var process: Process?
    
    private(set) var currentStatus: MediaStatus?
    
    private init() {}
    
    static func startMonitoring() {
        guard !shared.isMonitoring else { return }
        shared.isMonitoring = true
        shared.launchSidecar()
    }
    
    private func launchSidecar() {
        let script = """
        import Foundation

        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        guard handle != nil else { exit(1) }

        typealias GetInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        let symGet = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        guard let sym = symGet else { exit(1) }
        let getInfo = unsafeBitCast(sym, to: GetInfoFunction.self)

        var isFirst = true
        var lastTitle = ""
        var lastArtist = ""

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            getInfo(DispatchQueue.main) { info in
                let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                if isFirst || title != lastTitle || artist != lastArtist {
                    isFirst = false
                    lastTitle = title
                    lastArtist = artist
                    print("\\(title)|\\(artist)")
                    fflush(stdout)
                }
            }
        }
        RunLoop.main.run()
        """
        
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("h0ver_nowplaying.swift")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = [url.path]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                let lines = str.components(separatedBy: .newlines).filter { !$0.isEmpty }
                if let lastLine = lines.last {
                    let parts = lastLine.components(separatedBy: "|")
                    let title = parts.first ?? ""
                    let artist = parts.count > 1 ? parts[1] : ""
                    
                    DispatchQueue.main.async {
                        let isPlaying = !title.isEmpty
                        let status = MediaStatus(title: title, artist: artist, isPlaying: isPlaying)
                        self.currentStatus = status
                        NotificationCenter.default.post(name: NSNotification.Name("MediaStatusChanged"), object: nil, userInfo: ["status": status])
                    }
                }
            }
            
            do {
                try process.run()
                DispatchQueue.main.async {
                    self.process = process
                }
                process.waitUntilExit()
            } catch {
                print("Failed to launch sidecar: \\(error)")
            }
        }
    }
}
