import Foundation
import UIKit
import AVFoundation

class SoundManager: NSObject, AVAudioPlayerDelegate {
    static let shared = SoundManager()
    
    private var activePlayers = Set<AVAudioPlayer>()
    private let lock = NSLock()
    
    private override init() {
        super.init()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
        }
    }
    
    func playSound(named name: String) {
        guard let asset = NSDataAsset(name: name) else {
            print("⚠️ Sound asset not found: \(name)")
            return
        }

        // Off-main: NSDataAsset decode + AVAudioPlayer init + prepareToPlay possono bloccare
        // alcuni ms. playSound viene chiamato all'apertura del pacchetto (onTearComplete),
        // proprio quando parte l'animazione → farlo sul main causa un hitch sul primo frame.
        DispatchQueue.global(qos: .userInitiated).async {
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
