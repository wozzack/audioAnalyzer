import SwiftUI
import AudioKit
import AVFoundation

// slider value is not in sync with progress at all, and seeking shows progress
// at different value then intended. when attempting to seek backwards it adds the inverse amount of time to reverse instead of subtracting, so if i want to reverse two seconds back, instead it will skip forward by (current duration minus two seconds)

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
            /* 
             1. use .onEditingChanged to detect if manual seeking or not
             2. pause automatic timer progress updates while manual seeking
             3. apply built in seek operation when slider is released
             */
            Slider(value: $audioManager.progress, 
                   in: 0...1, 
                   onEditingChanged: { isEditing in
                audioManager.isManualSeeking = isEditing
                if !isEditing {
                    do {
                        // should only seek on release
                        // seeking() literally is just to seek, nothing more
                        try self.audioManager.manualSeeking(
                            prog: audioManager.progress)
                        // need to unpause time
                        
                        try audioManager.playAudio()
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging())
                    }
                } else {
                    // if we are editing, then we want to pause the audio
                    do {
                        // audioManager.manualSeekProgress = audioManager.progress
                        try audioManager.pauseAudio() 
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging())
                    }
                }
            })
            
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
