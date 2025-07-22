import SwiftUI
import AVFoundation
import AudioKit
import Waveform
import Foundation

/*
 Handle microphone input: NodeRecorder
 Handle Waveform: WaveformDataRequest
 */

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

        let audio = AudioObject(url: fileURL, name: s, duration: player.duration)
        return audio
    }
    
    func convertToAVAudioFile(s: String) throws -> AVAudioFile {
        guard let fileURL = Bundle.main.url(forResource: s, withExtension: "mp3")
        else {
            throw AudioManagerError.GenericFailure
        }
        let file  = try AVAudioFile(forReading: fileURL)
        return file
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
    // make it work for N amount of generic channels later
    func downSampling(length: Int, file: AVAudioFile) throws -> Array<Float> {
        // need to find the amount of channels
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, 
            frameCapacity: AVAudioFrameCount(file.length))
        else {
            throw AudioManagerError.GenericFailure
        }
        
        try file.read(into: buffer)
        guard let sample = buffer.floatChannelData
        else {
            throw AudioManagerError.GenericFailure
        }
        // cause does not conform to type Sequence, need to wrap it
        let firstChannel = UnsafeBufferPointer(
            start: sample[0],
            count: Int(buffer.frameLength))
        let secondChannel = UnsafeBufferPointer(
            start: sample[1],
            count: Int(buffer.frameLength))
        
        // just displaying one channel for ease of implementation for now
        let averageChannel = zip(firstChannel, secondChannel).map {
            ($0 + $1) / 2.0 }
        var downSample: [Float] = []
        for i in stride(from: 0, to: Int(buffer.frameLength), by: length) {
            downSample.append(averageChannel[i])
        }
        return Array(downSample)
    }
    
    
    // should also handle buffer loading so we can preload waveform visual
    func loadAudio(audio: AudioObject) throws {
        do {
            let loadingFile = try AVAudioFile(forReading: audio.url)
            // loads in waveform
            _ = try SampleBuffer(samples: downSampling(length: 300, file: loadingFile))
            
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
