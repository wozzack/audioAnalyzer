import AVFoundation
import AudioKit
import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    @StateObject var waveformView = WaveformView()
    @StateObject var graphManager = GraphManager()
    var displaySize = CGRect(x: 0, y: 0, width: 300, height: 600)
    
    @State var song: String = "misatowav"
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
                            //print(error.errorLogging())
                            //print("Raw error: \(error)")
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
                    if let _ = audioManager.player.file, audioManager.isLoaded {
                        do {
                            //  grabs raw data from the AVAudioFile and processes it via unique downsampling technique, we find issue with the dsData returning nil after it tries the below function
                            //let testFile = try makeDummyAVAudioFile()
                            print("About to call processAudio...")
                            try graphManager.visualModel?.processAudio(AVFile: audioManager.player.file!)
                            
                            // takes the processed data in the class and converts it into a correpsonding path object via normalization scaling.
                            let path = try graphManager.visualModel?.drawGraph(rect: displaySize)
                            context.stroke(path!, with: .color(graphManager.graphColor))
                        } catch {
                            //print("canvas failure")
                            //print((error as? VisualGraphError)?.errorLogging() as Any)
                        }
                    } else {
                        let placeholderText = Text("No audio loaded")
                        context.draw(placeholderText, at: CGPoint(x: size.width / 2, y: size.height / 2))
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


