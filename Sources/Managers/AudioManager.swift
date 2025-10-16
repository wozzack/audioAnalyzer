/*
 Handle microphone input: NodeRecorder
 Handle Waveform: WaveformDataRequest
 */

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
     accidental microseeking and existence. 
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

    func stopTimer() throws {
        guard timeToken != nil
        else {
            throw AudioManagerError.GenericFailure(funcName: "stopTimer", reason: "timeToken is nil, cannot stop timer")
        }
        timeToken?.invalidate()
        timeToken = nil
    }

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

    // basically pauseAudio() but we reset the progress to 0 too
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

    func addToPlaylist(audio: AudioObject) throws {
        guard !playlist.contains(audio) else {
            throw AudioManagerError.GenericFailure(funcName: "addToPlaylist", reason: "audio already exists in playlist, cannot add duplicate")
        }
        playlist.append(audio)
    }

    func clearPlaylist() {
        playlist = []
    }

    // should also handle buffer loading so we can preload waveform visual
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

    func removeFromPlaylist(audio: AudioObject) throws {
        guard let index = playlist.firstIndex(of: audio) else {
            throw AudioManagerError.GenericFailure(funcName: "removeFromPlaylist", reason: "audio does not exist in playlist, cannot remove")
        }
        playlist.remove(at: index)
    }

    func convertToAudioObject(s: String) throws -> AudioObject {
        // confirm it exists in our app bundle, want to be general for any file type
        // i want it to be able to auto detect file type by given string, will search in bundle and if multiple exists of diifferent file type, ask to specify file type in the string itself
        // given "misato.mp3", it will search for misato.mp3 in the bundle and if it exists, return the file URL for that resource
        let regexFilePattern = try Regex("[a-zA-Z0-9_]+\\.(wav|flac|mp3|m4a|aac)$")
        
        guard s.contains(regexFilePattern)
        else {
            throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject", reason: "Invalid string input.")
        }
            // locate file type and then extract the file name and extension from the string
        let fileExtension = String(s.split(separator: ".")[1])
        let fileName = String(s.split(separator: ".")[0])
        // if confirms to pattern, then start processing the string to extract the file name and extension
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension)
        else {
            throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject", reason: "Failed to find file URL for resource \(s).wav")
        }
        do {
            let AVFile = try AVAudioFile(forReading: fileURL)
            let audio = AudioObject(url: fileURL, name: s, duration: AVFile.duration, file: AVFile)
            return audio
        } catch {
            throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject", reason: "failed to create AVAudioFile for resource \(s).wav")
        }
    }

    func convertToAVAudioFile(s: String) throws -> AVAudioFile {
        let regexFilePattern = "[a-zA-Z0-9_]+\\.(wav|flac|mp3|m4a|aac)$"
        guard s.contains(regexFilePattern)
        else {
            throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile", reason: "Invalid string input.")
        }
            // locate file type and then extract the file name and extension from the string
        let fileExtension = String(s.split(separator: ".")[1])
        let fileName = String(s.split(separator: ".")[0])
        // want to be general for any file type
        guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension)
        else {
            throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile", reason: "failed to find file URL for resource \(s).wav")
        }
        do {
            let file = try AVAudioFile(forReading: fileURL)
            return file
        } catch {
            throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile", reason: "failed to create AVAudioFile for resource \(s).wav")
        }
    }
}
