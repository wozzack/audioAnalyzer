import SwiftUI
import AudioKit
import AVFoundation

// currentTime is jerking me around

struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    @State var song: String = "misato"
    @State var errorMessage: String?
    @State var isPlaylistShowing: Bool = false
    @State var progressSlider: Double = 0.0
    
    var body : some View {
        VStack {
            Button(audioManager.isPlaying ? "Pause" : "Play") {
                do {
                    if audioManager.player.isPlaying {
                        try audioManager.pauseAudio()
                    } else {
                        try audioManager.playAudio()
                    }
                } catch {
                    print((error as? AudioManagerError)?.errorLogging())
                }
            }.padding(20)
         
            Slider(value: $progressSlider, 
                   in: 0...1, 
                   onEditingChanged: { isEditing in
                audioManager.isManualSeeking = isEditing
                if !isEditing {
                    do {
                        // should only seek on release
                        // seeking() literally is just to seek, nothing more
                        print(progressSlider)
                        try self.audioManager.manualSeeking(
                            prog: progressSlider)
                        // need to unpause time
                        print("Finished manual seek. Current time is: ", audioManager.player.currentTime)
                        try audioManager.playAudio()
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging())
                    }
                } else {
                    // if we are editing, then we want to pause the audio
                    do {
                        progressSlider = audioManager.progress
                        print("Started editing. Current time is: ", audioManager.player.currentTime)
                        try audioManager.pauseAudio() 
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging())
                    }
                }
            })
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
                    print((error as? AudioManagerError)?.errorLogging())
                }
                
            }.padding(20)
            TextField("Enter song name: ", text: $song)
                .multilineTextAlignment(
                .center)
                .padding(20)
                .onSubmit {
                    do {
                        let audio = try audioManager.convertToAudioObject(s: song)
                        try audioManager.addToPlaylist(audio: audio)
                        song = ""
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging())
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
                            audioFile in Button() {
                                do {
                                    try audioManager.loadAudio(audio: audioFile)
                                    audioManager.isLoaded = true
                                } catch {
                                    print((error as? AudioManagerError)?.errorLogging())
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
