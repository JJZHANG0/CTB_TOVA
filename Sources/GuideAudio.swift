import AVFoundation

final class GuideAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

    func stop() {
        completion = nil
        player?.stop()
        player = nil
    }

    func play(_ index: Int, finished: (() -> Void)? = nil) {
        stop()
        let url = Bundle.main.url(forResource: "guide" + String(index), withExtension: "mp3")
        guard let url, let audio = try? AVAudioPlayer(contentsOf: url) else { finished?(); return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord { try? session.setCategory(.playback, options: [.duckOthers]) }
        try? session.setActive(true)
        player = audio
        completion = finished
        audio.delegate = self
        if !audio.play() { stop(); finished?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        let callback = completion
        stop()
        callback?()
    }
}
