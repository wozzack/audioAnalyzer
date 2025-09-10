
import Testing
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
    
    @Test func playback() throws {
        let audioManager = AudioManager()
        try audioManager.addToPlaylist(audio: convertToAudioObject(s: "misato.mp3"))
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try audioManager.playAudio()
        #expect(audioManager.player.status == .playing, "AudioManager player should be in started status after calling playAudio.")
        try audioManager.pauseAudio()
        #expect(audioManager.player.status == .paused, "AudioManager player should be in paused status after calling pauseAudio.")
        try audioManager.playAudio()
        #expect(audioManager.player.status == .playing, "AudioManager player should be in started status after calling playAudio again after stopping.")
        try audioManager.stopAudio()
        #expect(audioManager.player.status == .stopped, "AudioManager player should be in stopped status after calling stopAudio.")
    }
    
    @Test func seeking() throws {
        let audioManager = AudioManager()
        try audioManager.addToPlaylist(audio: convertToAudioObject(s: "misato.mp3"))
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try audioManager.playAudio()
        try audioManager.manualSeeking(prog: 0.5)
        #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() / 2, "AudioManager player should be at halfway point of duration after seeking to 0.5 progress.")
    }
}
