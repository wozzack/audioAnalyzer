import AVFoundation
import AudioKit
import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    @StateObject var waveformView = WaveformView()
    @StateObject var graphManager = GraphManager()
    var displaySize = CGRect(x: 0, y: 0, width: 300, height: 600)
    
    @State var song: String = "misato"
    @State var errorMessage: String?
    @State var isPlaylistShowing: Bool = false
    @State var progressSlider: Double = 0.0
    
    var body: some View {
        HStack {
            VStack {
                HStack {
                    // Input Field
                    TextField("Enter song name: ", text: $song)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .onSubmit {
                            do {
                                let audio = try convertToAudioObject(s: song)
                                try audioManager.addToPlaylist(audio: audio)
                                song = ""
                            } catch {
                                print((error as? AudioManagerError)?.errorLogging() as Any)
                            }
                        }
                        .foregroundColor(.blue)
                    
                    // Add Song Button
                    Button("Add Song") {
                        do {
                            let audio = try convertToAudioObject(s: song)
                            try audioManager.addToPlaylist(audio: audio)
                            song = ""
                        } catch {
                            print((error as? AudioManagerError)?.errorLogging() as Any)
                        }
                    }
                    .padding(10)
                }
                
                // Playlist Title
                Text("Playlist")
                    .frame(width: 175, height: 25)
                    .border(Color(.red))
                
                // Playlist View
                ScrollView {
                    VStack {
                        ForEach(audioManager.playlist, id: \.self) { audioFile in
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
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .frame(width: 175, height: 250)
                .border(Color(.red))
                
                // Clear Playlist Button
                Button("Clear playlist.") {
                    audioManager.clearPlaylist()
                }
            }
            
            .frame(width: 200, height: 400)
            .border(Color(.orange))
            
            // Canvas View
            VStack {
                Canvas { context, size in
                    if let visualModel = graphManager.visualModel,
                       let audioFile = audioManager.currentAudioObject?.file
                    {
                        do {
                            // What does process audio do? Grabs raw data from the AVAudioFile and processes it via unique downsampling technique and sets as self.dsData. So in a way it's an intiailizer of the WaveformView object.
                            try visualModel.processAudio(AVFile: audioFile)
                        
                            // What does drawGraph do? It takes the processed data in the class and converts it into a correpsonding path object via normalization scaling.
                            let path = try visualModel.drawGraph(rect: displaySize)
                            context.stroke(path, with: .color(graphManager.graphColor))
                        } catch {
                            print((error as? VisualGraphError)?.errorLogging() as Any)
                        }
                    }
                }
                .frame(width: 300, height: 200)
                .border(Color(.blue))
                .padding(10)
                
                // Playback Button
                HStack {
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
                    }
                    .padding(10)
                    
                    // Time Display
                    Text("\(audioManager.player.currentTime, specifier: "%.1f")")
                    
                    // Seeking Bar
                    Slider(
                        value: $progressSlider,
                        in: 0...1,
                        onEditingChanged: { isEditing in
                            audioManager.isManualSeeking = isEditing
                            if !isEditing {
                                do {
                                    try self.audioManager.manualSeeking(prog: progressSlider)
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
                    .frame(width: 250, height: 25)
                    .onChange(of: audioManager.progress) { _, newState in
                        if !audioManager.isManualSeeking {
                            progressSlider = newState
                        }
                    }
                }
                .border(Color(.green))
            }
            .frame(width: 400, height: 400)
            .border(Color(.orange))
        }
    }
}

#Preview {
    ContentView()
}


