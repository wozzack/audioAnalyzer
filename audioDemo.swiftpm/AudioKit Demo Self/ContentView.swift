/*
 just some janky ui for testing backend
 contentview flow logic: is slider actively being changed? if so, run
 manualSeeking() on slider value and then run playAudio. else, update
 progressSlider and run pauseAudio() so the timer isnt updating when 
 the user is seeking

 need to update error handling in accordance with new error system
 */

import AVFoundation

import AudioKit

import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    @StateObject var graphManager = GraphManager()
    @State var song: String = "misato"
    @State var errorMessage: String?
    @State var isPlaylistShowing: Bool = false
    @State var progressSlider: Double = 0.0

    var body: some View {
        VStack {
            Text("AudioKit Demo")
                .font(.largeTitle)
                .padding(20)

            // main UI for graph interface
            Canvas { _, _ in

            }
            .frame(width: 300, height: 200)
            .border(Color.blue)

            Button(audioManager.isPlaying ? "Pause" : "Play") {
                do {
                    if audioManager.player.isPlaying {
                        try audioManager.pauseAudio()
                    } else {
                        try audioManager.playAudio()
                    }
                } catch {
                    print((error as? AudioManagerError)?.errorLogging() as Any)
                }
            }.padding(20)

            Slider(
                value: $progressSlider,
                in: 0...1,
                onEditingChanged: { isEditing in
                    audioManager.isManualSeeking = isEditing
                    if !isEditing {
                        do {
                            try self.audioManager.manualSeeking(
                                prog: progressSlider)
                            try audioManager.playAudio()
                        } catch {
                            print((error as? AudioManagerError)?.errorLogging() as Any)
                        }
                    } else {
                        do {
                            progressSlider = audioManager.progress
                            try audioManager.pauseAudio()
                        } catch {
                            print((error as? AudioManagerError)?.errorLogging() as Any)
                        }
                    }
                }
            )
            .onChange(of: audioManager.progress) {
                _, newState in
                if !audioManager.isManualSeeking {
                    progressSlider = newState
                }

            }
            Text("\(audioManager.player.currentTime, specifier: "%.0f")")
            Text("\(audioManager.progress, specifier: "%.1f")")

            Button(isPlaylistShowing ? "Hide Playlist" : "Show Playlist") {
                isPlaylistShowing.toggle()
            }.padding(20)
            Button("Add Song To Playlist") {
                do {
                    let audio = try audioManager.convertToAudioObject(s: song)
                    try audioManager.addToPlaylist(audio: audio)
                    song = ""
                } catch {
                    print((error as? AudioManagerError)?.errorLogging() as Any)
                }

            }.padding(20)
            TextField("Enter song name: ", text: $song)
                .multilineTextAlignment(
                    .center
                )
                .padding(20)
                .onSubmit {
                    do {
                        let audio = try audioManager.convertToAudioObject(s: song)
                        try audioManager.addToPlaylist(audio: audio)
                        song = ""
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging() as Any)
                    }
                }
                .foregroundColor(.blue)

            Button("Clear playlist.") {
                audioManager.clearPlaylist()
            }

            if isPlaylistShowing {
                ScrollView {
                    VStack {
                        ForEach(audioManager.playlist, id: \.self) {
                            audioFile in
                            Button {
                                do {
                                    try audioManager.loadAudio(audio: audioFile)
                                    audioManager.isLoaded = true
                                } catch {
                                    print((error as? AudioManagerError)?.errorLogging() as Any)
                                }
                            } label: {
                                HStack {
                                    Text(audioFile.name)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
