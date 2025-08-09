import Combine
import AVFoundation

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var playingID: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var isPlaying: Bool = false

    private var timeObserver: Any?
    var player: AVPlayer?

    func streamMP3(from urlString: String, id: String) {
        guard let url = URL(string: urlString) else {
            print("❌ Неверный URL: \(urlString)")
            return
        }

        let playerItem = AVPlayerItem(url: url)
        self.player = AVPlayer(playerItem: playerItem)
        self.playingID = id
        self.currentTime = 0
        self.duration = 1
        self.isPlaying = true

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            if let total = self.player?.currentItem?.duration.seconds, total.isFinite {
                self.duration = total
            }
        }

        player?.play()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time)
    }

    func stop() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        playingID = nil
        currentTime = 0
        duration = 1
        isPlaying = false
    }
}
