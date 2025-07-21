//
//  AudioManager.swift
//  Audio App Backend stuff
//
//  Created by Kevin Truong on 6/29/25.

// implemented clamp seeking in order to stay within bounds, added previousSeekTime to prevent rapid successive seeks. added an explicit stopAudio vs pauseAudio method that resets the actual progress value too, and am attempting to simplify esstenial methods for debugging ease. also moving all audioManager logic from ContentView.swift to AudioManager.swift. created in moment instant variables in order to avoid operations with variables in constant flux

// when attempting to seek backwards, it seems to add the inverse amount of time to reverse instead of subtracting, so if i want to reverse two seconds back, instead it will skip forward by (current duration minus two seconds)

// idea: decouple slider value from player.currentTime temporarily and:
// 1. prevent overwrites during seeking
// 2. confirm value used in .seek(time:) is correct and up to date
// 3. make sure progress updates are one-way (user input -> player), not both

import SwiftUI
import AVFoundation
import AudioKit
import Foundation

func errorHandler(_ error: Error) {
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
    
    // variables for seeking bar, timeToken needed to remove observer later on
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
   
    // THIS IS THE ROOT OF ALL CORRUPTION INHERENT IN THE WORLD
    func manualSeeking(prog: Double) throws {
        // unwrap
        print("Started manual seek. Current time is: ", player.currentTime)
        guard let _ = currentAudioObject 
        else { 
            throw AudioManagerError.AudioObjectInitializationFailure
        }
        // print("seeking to progress=\(prog), duration=\(player.duration), calculated=\(prog * player.duration), currentTime=\(player.currentTime)")
        
        if let previousSeek = previousSeekTime, Date().timeIntervalSince(previousSeek) < 0.1 {
            return
        }
        print("Checked for rapid successive seeks. Current time is: ", player.currentTime)
        previousSeekTime = Date()

        let newTime = prog * player.duration
        print("Declared newTime to be: ", newTime)
        // shouldnt i set this to true instead of false?
        // isManualSeeking = false
        isManualSeeking = true
        print("Set isManualSeeking to true. Current time is: ", player.currentTime)
        let timeLimit = min(max(newTime, 0), player.duration)
        print("Seeking to: ", timeLimit)
        player.seek(time: timeLimit - player.currentTime)
        // WHEN I SEEK, IT ADDS THE TIME TO THE CURRENTTIME FOR SOME REASON
        print("Finished player seek. Current time is: ", player.currentTime)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.progress = self.player.duration > 0 ? self.player.currentTime / self.player.duration : 0
            self.isManualSeeking = false
        }
    }
    
    func startTimer() throws {
        timeToken?.invalidate()
        timeToken = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            // guard let self = self, !self.isManualSeeking 
            guard let self = self
            else { return }
            
            if (self.previousSeekTime != nil && Date().timeIntervalSince(self.previousSeekTime!) < 0.3) {
                return
            }
            
            let instantTime = player.currentTime
            let instantDuration = player.duration
            self.progress = instantDuration > 0 ? instantTime / instantDuration : 0

            if player.currentTime == player.duration {
                try? stopAudio()
                print("reached the end!")
            }
        }
        print("Started timer, Current time is: ", player.currentTime)
    }
    
    func stopTimer() throws {
        guard let _ = timeToken 
        else {
            throw AudioManagerError.TimeSeekingFailure
        }
        timeToken?.invalidate()
        timeToken = nil
        print("Stopped timer. Current time is: ", player.currentTime)
    }
    
    // player start() vs play() vs resume()
    func playAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        do { 
            player.start()
            print("Started audio. Current time is: ", player.currentTime)
            try startTimer()
            isPlaying = true
        } catch {
            print(player.isStarted)
        }
    }
    
    func resumeAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        player.resume()
        print("Resumed audio. Current time is: ", player.currentTime)
        do {
            try startTimer()
            isPlaying = true
        } catch {
            print("didnt resume")
        }
    }
    
    func pauseAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        player.pause()
        print("Paused audio. Current time is: ", player.currentTime)
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
        print("Stopped audio. Current time is: ", player.currentTime)
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
