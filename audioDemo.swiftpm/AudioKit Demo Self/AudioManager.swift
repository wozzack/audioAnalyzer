/*
 implemented clamp seeking in order to stay within bounds, added 
 previousSeekTime to prevent rapid successive seeks. added an explicit stopAudio 
 vs pauseAudio method that resets the actual progress value too, and am attempting 
 to simplify esstenial methods for debugging ease. also moving all audioManager 
 logic from ContentView.swift to AudioManager.swift. created in moment instant 
 variables in order to avoid operations with variables in constant flux

 decouple slider value from player.currentTime temporarily and:
 1. prevent overwrites during seeking
 2. confirm value used in .seek(time:) is correct and up to date
 3. make sure progress updates are one-way (user input -> player), not both
*/

import SwiftUI
import AVFoundation
import AudioKit
import Foundation

func errorHandler(_ error: Error) {
    // optional cast in case of missing AudioManagerError
    if let audioError = error as? AudioManagerError {
        print(audioError.errorLogging())
    } else {
        print("Unhandled error.")
    }
}

public class AudioManager: ObservableObject {

    struct AudioObject: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let name: String
        let duration: Double
    }
    
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
     accidental microseeking and existence. 
     */
    func manualSeeking(prog: Double) throws {
        
        guard let _ = currentAudioObject 
        else { 
            throw AudioManagerError.AudioObjectInitializationFailure
        }
        
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
            self.progress = self.player.duration > 0 ? self.player.currentTime / self.player.duration : 0
            self.isManualSeeking = false
        }
    }
    
    /*
     startTimer: invalidates any timeToken that might be there, then schedules a 
     cycle to run every 0.1 seconds that will either update the progress variable 
     or do nothing depending on isManualSeeking. also runs a check for if the 
     audio finished playing and resets if so.
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
            if (self.previousSeekTime != nil && Date().timeIntervalSince(self.previousSeekTime!) < 0.3) {
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
    
    func stopTimer() throws {
        guard let _ = timeToken 
        else {
            throw AudioManagerError.TimeSeekingFailure
        }
        timeToken?.invalidate()
        timeToken = nil
    }
    
    func playAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        do { 
            player.start()
            try startTimer()
            isPlaying = true
        } catch {
            print(player.isStarted)
        }
    }
    
    func pauseAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        do { 
            player.pause()
            try stopTimer()
            isPlaying = false
        } catch {
            print("didnt pause timer")
        }
    }
    
    // basically pauseAudio() but we reset the progress to 0 too
    func stopAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        do {
            player.stop()
            try stopTimer()
            isPlaying = false
            progress = 0.0
        } catch {
            print("didnt stop timer")
        }
        
    }
    func convertToAudioObject(s: String) throws -> AudioObject {
        guard let fileURL = Bundle.main.url(forResource: s, withExtension: "mp3") 
        else {
            throw AudioManagerError.ConvertToAudioObjectFailure
        }
        // need to grab duration from mp3 file, eh duration woirks for now lol
        let audioFile = AVAsset(url: fileURL)
        return AudioObject(url: fileURL, name: s, duration: CMTimeGetSeconds(audioFile.duration)) // this doesnt make sense, its already in seconds format??? CMTime -> Seconds right???
    }
    
    func addToPlaylist(audio: AudioObject) throws {
        guard !playlist.contains(audio) else {
            throw AudioManagerError.AddPlaylistFailure
        }
        playlist.append(audio)
    }
    
    func clearPlaylist() {
        playlist = []
    }

    func loadAudio(audio: AudioObject) throws {
        do {
            let loadingFile = try AVAudioFile(forReading: audio.url)
            try player.load(file: loadingFile)
            isLoaded = true
            currentAudioObject = audio
            // startObservingTime()
        } catch {
            throw AudioManagerError.LoadAudioFailure
        }
    }

    func removeFromPlaylist(audio: AudioObject) throws {
        guard let index = playlist.firstIndex(of: audio) else {
            throw AudioManagerError.DeleteFromPlaylistError
        }
        playlist.remove(at: index)
    }
}
