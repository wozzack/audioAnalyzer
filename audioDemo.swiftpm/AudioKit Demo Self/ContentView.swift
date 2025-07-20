import SwiftUI
import AudioKit
import AVFoundation


struct ContentView: View {
    /*
     attempting to move any audioManager logic out of contentView and back in the class file
     */
    @StateObject var audioManager = AudioManager()
    @State var song: String = "misato"
    @State var errorMessage: String?
    @State var isPlaylistShowing: Bool = false
    
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
                audioManager.isSeeking = isEditing
                if !isEditing {
                    do {
                        // should only seek on release
                        try self.audioManager.seeking(
                            prog: self.audioManager.progress)
                    } catch {
                        print((error as? AudioManagerError)?.errorLogging())
                    }
                }
            })
            // occurs AFTER gesture is finished
            /*
            .onChange(of: audioManager.progress) { newValue in
                do {
                    try audioManager.seeking(prog: newValue)
                } catch {
                    print((error as? AudioManagerError)?.errorLogging())
                }
            }
             */
            
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
