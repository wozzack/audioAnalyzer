//
//  AudioManager.swift
//  Audio App Backend stuff
//
//  Created by Kevin Truong on 6/29/25.

// implemented clamp seeking in order to stay within bounds, added previousSeekTime to prevent rapid successive seeks. added an explicit stopAudio vs pauseAudio method that resets the actual progress value too, and am attempting to simplify esstenial methods for debugging ease. also moving all audioManager logic from ContentView.swift to AudioManager.swift. created in moment instant variables in order to avoid operations with variables in constant flux

import SwiftUI
import AVFoundation
import AudioKit
import Foundation

func errorHandler(_ error: Error) {
    // optional cast in case not of AudioManagerError
    if let audioError = error as? AudioManagerError {
        // hand over to console function
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
    
    // variables for seeking bar, timeToken needed to remove observer later on
    // @Published var progress: Double = 0.0
    @Published var timeToken: Timer? = nil
    @Published var currentAudioObject: AudioObject? = nil
    @Published var previous: Bool = false
    @Published var progress: Double = 0.0
    @Published var isSeeking: Bool = false
    @Published var previousSeekTime: Date? = nil
    // cant access properties before object can confirm self
     
    init() {
        engine.output = player
        try? engine.start()
    }
   
    // something done fucked up in here, why am i assuming that prog is updated value
    // well it should be but i put the wrong value in there
    func seeking(prog: Double) throws {
        // unwrap
        guard let current = currentAudioObject 
        else { 
            throw AudioManagerError.AudioObjectInitializationFailure
        }
        // TO AVOID RAPID SUCCESSIVE SEEKS
        if let previousSeek = previousSeekTime, Date().timeIntervalSince(previousSeek) < 0.1 {
            return
        }
        previousSeekTime = Date()
        
        let newTime = prog * player.duration
        isSeeking = false
        
        // ensures the value we end up using doesnt go beyond the bounds
        let timeLimit = min(max(newTime, 0), current.duration)
        
        // procedural stuff
        player.seek(time: timeLimit)
        progress = prog
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isSeeking = false
        }

    }
    // previousTime and currentTime overlap, relies on if previous
    // make sure to initialize Timer object first
    // startTimer(): invalidates the timer object, then creates a timer that checks if the user is NOT seeking, and if so then updates the progress variable. if user is seeking, does nothing as the functio`n call to pauseTimer() is done in UI logic
    func startTimer() throws {
        // always gotta make sure or else funky stuff happens
        timeToken?.invalidate()
        timeToken = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            // weak self is to avoid retaining cycle inside closure
            
            [weak self] _ in
            // confirm existence of self and unwrapping to be non optional
            guard let self = self, !self.isSeeking 
            else { return }
        
            let instantTime = player.currentTime
            let instantDuration = player.duration
            self.progress = instantDuration > 0 ? instantTime / instantDuration : 0
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
    
    // player start() vs play()
    func playAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        player.play()
        do { 
            try startTimer()
            isPlaying = true
        } catch {
            print("didnt start timer")
        }
    }
    
    func pauseAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        player.pause()
        do { 
            try stopTimer()
            isPlaying = false
        } catch {
            print("didnt pause timer")
        }
    }
    
    func stopAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        player.stop()
        do {
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
