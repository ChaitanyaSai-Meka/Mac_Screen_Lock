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
    private var timer: Timer?
    
    private(set) var currentStatus: MediaStatus?
    
    private let getInfoSym: UnsafeMutableRawPointer?
    typealias GetInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    
    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        if let h = handle {
            getInfoSym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo")
        } else {
            getInfoSym = nil
        }
    }
    
    static func startMonitoring() {
        guard !shared.isMonitoring else { return }
        shared.isMonitoring = true
        shared.startTimer()
    }
    
    static func stopMonitoring() {
        guard shared.isMonitoring else { return }
        shared.isMonitoring = false
        shared.timer?.invalidate()
        shared.timer = nil
    }
    
    private func startTimer() {
        guard let sym = getInfoSym else { return }
        let getInfo = unsafeBitCast(sym, to: GetInfoFunction.self)
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            getInfo(DispatchQueue.main) { info in
                let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                Task { @MainActor [title, artist] in
                    self?.processInfo(title: title, artist: artist)
                }
            }
        }
    }
    
    private func processInfo(title: String, artist: String) {
        
        let isPlaying = !title.isEmpty
        let status = MediaStatus(title: title, artist: artist, isPlaying: isPlaying)
        
        if currentStatus?.title != title || currentStatus?.artist != artist || currentStatus?.isPlaying != isPlaying {
            self.currentStatus = status
            NotificationCenter.default.post(name: NSNotification.Name("MediaStatusChanged"), object: nil, userInfo: ["status": status])
        }
    }
}
