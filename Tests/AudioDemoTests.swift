//
//  AudioDemoTests.swift
//  AudioDemoTests
//
//  Created by Kevin Truong on 9/8/25.
//
//
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
    @Test func stringsToPlaylist () {
        let strings = ["misato.mp3", "asuka.wav", "rei.flac", "kaji.m4a"]
    }
}



@Test func AudioManagerTest() {
    #expect(true == true, "True should be equal to true")
}
