import Foundation
import UIKit
import AVFoundation

nonisolated final class SoundManager: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    static let shared = SoundManager()

    private static let configureAudioSession: Void = {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
        }
    }()

    private var activePlayers = Set<AVAudioPlayer>()
    private let lock = NSLock()

    private override init() {
        super.init()
    }
    
    func playSound(named name: String) {
        guard let asset = NSDataAsset(name: name) else {
            print("⚠️ Sound asset not found: \(name)")
            return
        }

        // Configure once on the playback queue. prepareToPlay activates the session
        // there too, keeping audio setup off the main thread during animations.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.configureAudioSession
            do {
                let player = try AVAudioPlayer(data: asset.data, fileTypeHint: "mp3")
                player.delegate = self
                player.prepareToPlay()

                self.lock.lock()
                self.activePlayers.insert(player)
                self.lock.unlock()

                player.play()
            } catch {
                print("⚠️ Failed to play sound \(name): \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lock.lock()
        activePlayers.remove(player)
        lock.unlock()
    }
}
