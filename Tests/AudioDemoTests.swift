
import Testing
import SwiftUI
import AudioKit
import AVFoundation

@testable import AudioDemo

class AudioManagerTestSuite {
    init() {
        print("Starting AudioManager Test Suite.")
    }
    
    deinit {
        print("Ending AudioManager Test Suite.")
    }
    // need tests for seeking bar, playlist, loading audio, and convert helper functions
    // lossy formats: mp3, aac
    // lossless formats: flac, alac
    // uncompressed formats: wav, aiff
    @Test func stringsToPlaylist() throws {
        let audioManager = AudioManager()
        let validStrings = ["misato.mp3", "asuka.wav", "rei.flac", "kaji.m4a"]
        let invalidStrings = ["invalidfile.txt", ".wav", "audiofile.mp3.mp4", ""]
        for string in validStrings {
            do {
                try audioManager.addToPlaylist(audio: convertToAudioObject(s: string))
            } catch {
                throw AudioManagerError.GenericFailure(funcName: "addToPlaylist", reason: "Failed to add valid audio object to playlist for string \(string)")
            }
        }
        for string in invalidStrings {
            do {
                try audioManager.addToPlaylist(audio: convertToAudioObject(s: string))
                
            } catch {
                // expected error, do nothing
                #expect(validStrings.count == audioManager.playlist.count, "Playlist should only contain valid audio objects added from valid strings.")
            }
        }
        #expect(audioManager.playlist.count == validStrings.count, "Playlist should contain only valid audio objects added from valid strings.")
    }
    
    @Test func loadFromPlaylist() throws {
        let audioManager = AudioManager()
        let validStrings = ["misato.mp3", "asuka.wav", "rei.flac", "kaji.m4a"]
        for string in validStrings {
            do {
                try audioManager.addToPlaylist(audio: convertToAudioObject(s: string))
            } catch {
                throw AudioManagerError.GenericFailure(funcName: "addToPlaylist", reason: "Failed to add valid audio object to playlist for string \(string)")
            }
        }
        
        for audio in audioManager.playlist {
            do {
                try audioManager.loadAudio(audio: audio)
            } catch {
                throw AudioManagerError.GenericFailure(funcName: "loadAudio", reason: "Failed to load audio object from playlist for audio \(audio.name)")
            }
            #expect(audioManager.isLoaded == true, "AudioManager should have successfully loaded audio object \(audio.name) from playlist.")
        }
    }
    
    // should also test pause on stop for invaid
    @Test func playback() throws {
        let audioManager = AudioManager()
        try audioManager.addToPlaylist(audio: convertToAudioObject(s: "misato.mp3"))
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        do {
            try audioManager.playAudio()
            #expect(audioManager.player.status == .playing, "AudioManager player should be in started status after calling playAudio.")
            try audioManager.pauseAudio()
            #expect(audioManager.player.status == .paused, "AudioManager player should be in paused status after calling pauseAudio.")
            try audioManager.playAudio()
            #expect(audioManager.player.status == .playing, "AudioManager player should be in started status after calling playAudio again after stopping.")
            try audioManager.stopAudio()
            #expect(audioManager.player.status == .stopped, "AudioManager player should be in stopped status after calling stopAudio.")
        }
        
        do {
            try audioManager.pauseAudio()
        } catch let error {
            #expect(error is AudioManagerError)
        }
    }
    
    @Test func seeking() throws {
        let audioManager = AudioManager()
        try audioManager.addToPlaylist(audio: convertToAudioObject(s: "misato.mp3"))
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try audioManager.playAudio()
        try audioManager.manualSeeking(prog: 0.5)
        #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() / 2, "AudioManager player should be at halfway point of duration after seeking to 0.5 progress.")
        try audioManager.manualSeeking(prog: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() * 0.8, "AudioManager player should be at 80% point of duration after seeking to 0.8 progress.")
        }
    
        try audioManager.manualSeeking(prog: 0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() * 0.25, "AudioManager player should be at 25% point of duration after seeking to 0.25 progress.")
        }
    }
}

class CanvasManagerTestSuite {
    init() {
        print("Starting CanvasManager Test Suite.")
    }
    
    deinit {
        print("Ending CanvasManager Test Suite.")
    }
    
    @Test func changeGraph() throws {
        let testFile = try convertToAudioObject(s: "misato.mp3")
        let testFile2 = try convertToAudioObject(s: "asuka.wav")
        let canvasManager = CanvasManager()
        do {
            try canvasManager.changeGraph(newGraph: .waveform, file: testFile.file)
            #expect(canvasManager.visualModel is WaveformView, "visualModel is of wrong type")
            #expect(canvasManager.visualModel!.dsData != nil, "dsData is nil")
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to change visualModel and it's properties correctly.")
        }
        
        do {
            try canvasManager.changeGraph(newGraph: .spectrogram, file: testFile2.file)
            #expect(canvasManager.visualModel is SpectrogramView, "visualModel is of wrong type")
            #expect(canvasManager.visualModel!.dsData != nil, "dsData is nil")
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to change visualModel and it's properties correctly.")
        }
    }
    
    @Test func isGraphShowing() {
        let canvasManager = CanvasManager()
        canvasManager.clearGraph()
        #expect(canvasManager.graphShowing == false)
    }
    
}

class GraphManagerTestSuite {
    init() {
        print("Starting GraphManager Test Suite.")
    }
    
    deinit {
        print("Ending GraphManager Test Suite.")
    }
    // test for success and failure scenarios, check relevant states for correct values, not just existance. test for single and multi channel audio files, pass invalid file and assert the correct error is thrown.
    @Test func waveformProcessing() throws {
        // prechecklist stuff type shit
        let audioManager = AudioManager()
        let canvasManager = CanvasManager()
        let testAudioObject = try convertToAudioObject(s: "misato.mp3")
        let testAudioObject2 = try convertToAudioObject(s: "asuka.wav")
        try audioManager.addToPlaylist(audio: testAudioObject)
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject.file)
        
        // success
        do {
            try canvasManager.visualModel?.processAudio(AVFile: testAudioObject.file)
            // check that they are not nil
            #expect(canvasManager.visualModel?.rawData != nil)
            #expect(canvasManager.visualModel?.dsData != nil)
            #expect((canvasManager.visualModel?.dsData?.count ?? 0) > 0, "dsData should not be empty" )
            
            // check that dsData values are valid, normalized, and in logical ordering
            if let dsData = canvasManager.visualModel?.dsData {
                for (min, max) in dsData {
                    #expect(min <= max, "min values range exceeds that of max values range")
                    #expect(min >= -1.0 && max <= 1.0, "min and max values are not normalized between -1.0 and 1.0")
                }
            }
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "processAudio", reason: "failed to process audio for testAudioObject1")
        }
        
        // failure due to mismatched files
        do {
            try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject2.file)
        } catch let error {
            #expect(error is GraphManagerError)
        }
        
        do {
            try canvasManager.visualModel?.processAudio(AVFile: testAudioObject2.file)
            try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject2.file)
            // check that they are not nil
            #expect(canvasManager.visualModel?.rawData != nil)
            #expect(canvasManager.visualModel?.dsData != nil)
            #expect((canvasManager.visualModel?.dsData?.count ?? 0) > 0, "dsData should not be empty" )
            
            // check that dsData values are valid, normalized, and in logical ordering
            if let dsData = canvasManager.visualModel?.dsData {
                for (min, max) in dsData {
                    #expect(min <= max, "min values range exceeds that of max values range")
                    #expect(min >= -1.0 && max <= 1.0, "min and max values are not normalized between -1.0 and 1.0")
                }
            }
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "processAudio", reason: "failed to process audio for testAudioObject2")
        }
    }
    
    @Test func waveformDrawing() throws {
        let audioManager = AudioManager()
        let canvasManager = CanvasManager()
        let testAudioObject = try convertToAudioObject(s: "misato.mp3")
        try audioManager.addToPlaylist(audio: testAudioObject)
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject.file)
        try canvasManager.visualModel?.processAudio(AVFile: testAudioObject.file)
        let displaySize = CGRect(x: 0, y: 0, width: 300, height: 600)
        let displaySize2 = CGRect(x: 0, y: 0, width: 600, height: 300)
        
        // what do i want to check for in the pathobject?
        
        let pathObject = try canvasManager.visualModel?.drawGraph(rect: displaySize)
        
        #expect(pathObject != nil)
        
    }
}

