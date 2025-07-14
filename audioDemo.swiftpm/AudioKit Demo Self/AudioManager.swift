//
//  Item.swift
//  Audio App Backend stuff
//
//  Created by Kevin Truong on 6/29/25.

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
    /*
     USE BUILT IN isSeeking FLAG
     so if i seek backwards to a value that makes it jump higher than the actual duration, it bugs out
     
     addToPlaylist: add audioObject to playlist
     loadAudio: readies audio in player
     playOrPause: plays or pauses audio in player depending on state
     convertToURL: converts string into audioObject type
     startTimer: starts global timer on player 
     pauseTimer: destroys timer and deallocate to prevent leaks, will save past time
     removeFromPlaylist: removes from playlist
     loopAudio: tells player to toggle isLooping, might be redunant
     manualSeek: pauses global timer, changes progress and related variables
     
     TODO
     - seeking bar functionality
         - currently seeking forward from the slider works but going backwards glitches
         - previous flag not working
     - add indication that song from playlist is selected
     - add loop functionality
     - redo error detection system
         - further categorize different errors for ease of reading
     - manually unwrap initialization of audioObject struct for smoother coding
     - remove previousTime and rely on currentTime only (single source of truth)
     - send error messages to UI instead of console for viewability
     
     Note:
     String must be added to playlist before being played.
     To add to playlist, convert string into AudioObject,
     which requires converting the string into URL type and wrapping it as AudioObject.
     
     Note2: when an audio file is loaded, the buffering bar should be revealed and needs to be reset/configured everytime we change the loaded audio file
     */
    
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
    @Published var progress: Double = 0.0
    @Published var timeToken: Timer? = nil
    @Published var currentAudioObject: AudioObject? = nil
    @Published var previous: Bool = false
    @Published var previousTime: Double = 0.0
    @Published var isManualSeeking: Bool = false
    
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
        // if succeeds, get value. if thrown, return nil
        /*
        do {
            try pauseAudio()
        } catch {
            throw AudioManagerError.PlaybackFailure
        }
         */
        // 
        // isManualSeeking = true
        let newTime = prog * current.duration
        player.seek(time: newTime)
        previousTime = newTime
        progress = prog
        // if isPlaying { try? startTimer() }
    }
    // previousTime and currentTime overlap, relies on if previous
    // make sure to initialize Timer object first
    func startTimer() throws {
        // always gotta make sure or else funky stuff happens
        timeToken?.invalidate()
        timeToken = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            // weak self is to avoid retaining cycle inside closure
            [weak self] _ in
            // confirm existence of self and unwrapping to be non optional
            guard let self = self 
            else { return }
            
            //if self.player.isSeeking == false {
            let current = self.player.currentTime
            progress = current / self.player.duration
            self.previousTime = current
            //}
            // basically when user is not using slider
            /*
            if self.isManualSeeking == false {
                self.progress = self.player.currentTime / self.player.duration
                // player has started in the past
                let currentTime = self.player.currentTime
                if self.previous {
                    //self.progress = self.previousTime / self.player.duration
                    self.progress = self.previousTime / self.player.duration
                    // player has not even started audio yet
                } else {
                    self.progress = currentTime / self.player.duration
                }
                self.previousTime = currentTime
             
            }
             */
        }
    }
    
    func pauseTimer() throws {
        guard let _ = timeToken 
        else {
            throw AudioManagerError.TimeSeekingFailure
        }
        previousTime = progress * player.currentTime
        timeToken?.invalidate()
        timeToken = nil
    }
    
    func playAudio() throws {
        guard isLoaded else {
            throw AudioManagerError.PlaybackFailure
        }
        player.start()
        do { 
            try startTimer()
            isPlaying.toggle()
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
            try pauseTimer()
            isPlaying.toggle()
        } catch {
            print("didnt pause timer")
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

    // now this needs to handle the loading/configuration of the buffering bar?
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
