import AVFoundation

final class RepFeedbackPlayer {
    private var player: AVAudioPlayer?

    init(resourceName: String = "ah", fileExtension: String = "wav") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
        } catch {
            self.player = nil
        }
    }

    func playRepSound() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}
