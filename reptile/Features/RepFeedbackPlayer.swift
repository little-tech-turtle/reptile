import AVFoundation

struct ExerciseRepSound: Hashable {
    let resourceName: String
    let fileExtension: String

    init(resourceName: String, fileExtension: String = "wav") {
        self.resourceName = resourceName
        self.fileExtension = fileExtension
    }
}

final class RepFeedbackPlayer {
    private var players: [ExerciseRepSound: AVAudioPlayer] = [:]
    private var unavailableSounds: Set<ExerciseRepSound> = []

    init() {}

    func playRepSound(_ sound: ExerciseRepSound?) {
        guard let sound else { return }
        guard let player = player(for: sound) else { return }

        player.currentTime = 0
        player.play()
    }

    private func player(for sound: ExerciseRepSound) -> AVAudioPlayer? {
        if let player = players[sound] {
            return player
        }

        guard !unavailableSounds.contains(sound) else { return nil }

        guard let url = Bundle.main.url(forResource: sound.resourceName, withExtension: sound.fileExtension) else {
            unavailableSounds.insert(sound)
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[sound] = player
            return player
        } catch {
            unavailableSounds.insert(sound)
            return nil
        }
    }
}
