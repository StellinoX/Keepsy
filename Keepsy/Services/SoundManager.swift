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
        
        do {
            let player = try AVAudioPlayer(data: asset.data, fileTypeHint: "mp3")
            player.delegate = self
            player.prepareToPlay()
            
            lock.lock()
            activePlayers.insert(player)
            lock.unlock()
            
            player.play()
        } catch {
            print("⚠️ Failed to play sound \(name): \(error.localizedDescription)")
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        lock.lock()
        activePlayers.remove(player)
        lock.unlock()
    }
}
