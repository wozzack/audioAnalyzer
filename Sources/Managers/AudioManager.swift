import AVFoundation
import AudioKit
import Foundation
import SwiftUI
import Waveform

struct AudioObject: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let duration: Double
    let file: AVAudioFile
}

public class AudioManager: ObservableObject {

    let player = AudioPlayer()
    let engine = AudioEngine()

    @Published var isPlaying: Bool = false
    @Published var currentAudio: String? = nil
    @Published var playlist: [AudioObject] = []
    @Published var isPlaylistShowing: Bool = false
    @Published var isLoaded: Bool = false

    @Published var timeToken: Timer? = nil
    @Published var currentAudioObject: AudioObject? = nil
    @Published var progress: Double = 0.0
    @Published var isManualSeeking: Bool = false
    @Published var manualSeekProgress: Double = 0.0
    @Published var previousSeekTime: Date? = nil

    init() {
        engine.output = player
        try? engine.start()
    }

    /*
     manualSeeking: contains the actual player seek function. contains checks for
     accidental microseeking and existence
     @: called by ContentView; calls nothing
     needs: progress value we want to update to
     gives: updated previousSeekTime, updated isManualSeeking
     */
    func manualSeeking(prog: Double) throws {

        guard currentAudioObject != nil
        else {
            throw AudioManagerError.GenericFailure(funcName: "manualSeeking", reason: "no currentAudioObject loaded")
        }
        
        // protects aganst multiple seeks in rapid succession, which can cause issues with the player seeking to the wrong time
        if let previousSeek = previousSeekTime, Date().timeIntervalSince(previousSeek) < 0.1 {
            return
        }
        previousSeekTime = Date()

        let newTime = prog * player.duration
        isManualSeeking = true

        // clamp seeking in order to stay within bounds
        let timeLimit = min(max(newTime, 0), player.duration)

        // lord forgive the man who made this implementation, basically issue was that it would add timeLimit and currentTime together to act as the players new currentTime
        player.seek(time: timeLimit - player.currentTime)

        // runs async updating of the progress variable so that it chooses to match the audioPlayer state vs the state of the actual slider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.progress =
                self.player.duration > 0 ? self.player.currentTime / self.player.duration : 0
            self.isManualSeeking = false
        }
    }

    /*
     startTimer: invalidates any timeToken that might be there, then schedules a cycle to run every 0.1 seconds that will either update the progress variable or do nothing depending on isManualSeeking. also runs a check for if the audio finished playing and resets if so
     @: called by playAudio(); calls stopAudio()
     needs: nothing
     gives: updated progress, new timer
     */
    func startTimer() throws {
        timeToken?.invalidate()
        timeToken = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            // weak self is to avoid retaining cycle inside closure
            [weak self] _ in
            // ensures existence and that it isnt going offsync with the user slider
            guard let self = self, !self.isManualSeeking
            else { return }
            // a check against multiple seeks in rapid succession
            if self.previousSeekTime != nil
                && Date().timeIntervalSince(self.previousSeekTime!) < 0.3
            {
                return
            }
            // grabs constant values so we arent doing operations with variables in flux
            let instantTime = player.currentTime
            let instantDuration = player.duration
            self.progress = instantDuration > 0 ? instantTime / instantDuration : 0

            // checks if finished playing and resets if so, needs stricter checks
            if player.currentTime == player.duration {
                try? stopAudio()
            }
        }
    }
    
    /*
     stopTimer: deallocates timeToken
     @: called by pauseAudio() and stopAudio(); calls nothing
     needs: nothing
     gives: freed memory
     */
    func stopTimer() throws {
        guard timeToken != nil
        else {
            throw AudioManagerError.GenericFailure(funcName: "stopTimer", reason: "timeToken is nil, cannot stop timer")
        }
        timeToken?.invalidate()
        timeToken = nil
    }

    /*
     playAudio: starts player and timer and sets isStarted boolean flag
     @: called by ContentView; calls startTimer()
     needs: loaded audio file
     gives: new timer, updated isPlaying boolean flag
     */
    func playAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.GenericFailure(funcName: "playAudio", reason: "audio is not loaded, cannot play audio")
        }
        do {
            player.start()
            try startTimer()
            isPlaying = true
        } catch {
            print(player.isStarted)
        }
    }
    
    /*
     pauseAudio: pauses player and stops timer and sets isPlaying boolean flag
     @: called by ContentView; calls startTimer()
     needs: loaded audio file
     gives: freed memory, updated isPlaying boolean flag
     */
    func pauseAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.GenericFailure(funcName: "pauseAudio", reason: "audio is not loaded, cannot pause audio")
        }
        do {
            player.pause()
            try stopTimer()
            isPlaying = false
        } catch {
            throw AudioManagerError.GenericFailure(funcName: "pauseAudio", reason: "failed to pause audio and/or stop timer")
        }
    }
    /*
     stopAudio: basically pauseAudio() but we reset the progress to 0 too. stops player and stops timer and sets isPlaying boolean flag and progress to 0
     @: called by ContentView; calls startTimer()
     needs: loaded audio file
     gives: freed memory, updated isPlaying boolean flag, updated progress
     */
    func stopAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.GenericFailure(funcName: "stopAudio", reason: "audio is not loaded, cannot stop audio")
        }
        do {
            player.stop()
            try stopTimer()
            isPlaying = false
            progress = 0.0
        } catch {
            throw AudioManagerError.GenericFailure(funcName: "stopAudio", reason: "failed to stop audio and/or stop timer")
        }

    }
    /*
     addToPlaylist: takes an audioObject and appends it to playlist, includes check for duplication
     @: called by ContentView; calls nothing
     needs: audio object to add and non duplication in existing playlist
     gives: updated playlist
     */
    func addToPlaylist(audio: AudioObject) throws {
        guard !playlist.contains(audio) else {
            throw AudioManagerError.GenericFailure(funcName: "addToPlaylist", reason: "audio already exists in playlist, cannot add duplicate")
        }
        playlist.append(audio)
    }
    
    /*
     clearPlaylist: sets playlist to be an empty array
     @: called by ContentView; calls nothing
     needs: nothing
     gives: updated playlist
     */

    func clearPlaylist() {
        playlist = []
    }

    /*
     loadAudio: loads AVAudioFile, sets currentAudioObject, and sets boolean flag isLoaded
     @: called by ContentView; calls nothing
     needs: audio object
     gives: loaded player, updated currentAudioObject and booleanflag isLoaded
     */
    func loadAudio(audio: AudioObject) throws {
        do {
            let loadingFile = try AVAudioFile(forReading: audio.url)
            // loads in waveform
            try player.load(file: loadingFile)
            isLoaded = true
            currentAudioObject = audio
            // startObservingTime()
        } catch {
            throw AudioManagerError.GenericFailure(funcName: "loadAudio", reason: "failed to load audio file into player")
        }
    }
    
    /*
     removeFromPlaylist: removes audio object from playlist by first finding the index of said audio object
     @: called by ContentView; calls nothing
     needs: audioObject existing in current playlist
     gives: updated playlist
     */
    func removeFromPlaylist(audio: AudioObject) throws {
        guard let index = playlist.firstIndex(of: audio) else {
            throw AudioManagerError.GenericFailure(funcName: "removeFromPlaylist", reason: "audio does not exist in playlist, cannot remove")
        }
        playlist.remove(at: index)
    }
}
