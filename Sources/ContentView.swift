import AVFoundation
import AudioKit
import SwiftUI

struct ContentView: View {
    @StateObject var audioManager = AudioManager()
    @StateObject var waveformView = WaveformView()
    @StateObject var canvasManager = CanvasManager()
    @StateObject var micManager = MicManager()
    var displaySize = CGRect(x: 0, y: 0, width: 300, height: 600)
    
    @State var song: String = "misato.mp3"
    @State var errorMessage: String?
    @State var isPlaylistShowing: Bool = false
    @State var progressSlider: Double = 0.0
    @State var amplitudeLevel: Float = 0.0
    
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
                                // at failure will return AudioManagerError
                                let audio = try convertToAudioObject(s: song)
                                // will also present as AudioManagerError
                                try audioManager.addToPlaylist(audio: audio)
                                song = ""
                            } catch let error {
                                // print the error
                                // errorLogger(error: error)
                                // print the error description if it conforms to AudioManagerError
                                print(errorHandler(error))
                            }
                        }
                        .foregroundColor(.blue)
                    
                    // Add Song Button
                    Button("Add Song") {
                        do {
                            let audio = try convertToAudioObject(s: song)
                            try audioManager.addToPlaylist(audio: audio)
                            song = ""
                        } catch let error {
                            print(errorHandler(error))
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
                                    // loadAudio sets audioManager.player.file to be the current file we need
                                    try canvasManager.changeGraph(newGraph: .spectrogram, file: audioManager.player.file!)
                                    try canvasManager.visualModel?.processAudio(AVFile: audioManager.player.file!)
                                    audioManager.isLoaded = true
                                } catch let error {
                                    print(errorHandler(error))
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
            
            .frame(width: 200, height: 450)
            .border(Color(.orange))
            
            // Canvas View
            VStack {
                Canvas { context, size in
                    if let _ = audioManager.player.file, audioManager.isLoaded {
                        do {
                            //  grabs raw data from the AVAudioFile and processes it via unique downsampling technique, we find issue with the dsData returning nil after it tries the below function
                            let cgImage = try canvasManager.visualModel?.drawGraph(rect: displaySize, color: Color(.red), lineWidth: CGFloat(1.0)) // color actually doesnt do anything for spectrogram
                            
                            if let cgImage {
                                context.draw(Image(decorative: cgImage, scale: 1), in: displaySize)
                            }
                        } catch let error {
                            print(errorHandler(error))
                        }
                    } else {
                        let placeholderText = Text("\(micManager.ampLevel)")
                        context.draw(placeholderText, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    }
    
                }
                .onChange(of: audioManager.player.file) { _, newState in
                    // reruns canvas closure if loaded file is changed.
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
                        } catch let error {
                            print(errorHandler(error))
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
                                } catch let error {
                                    print(errorHandler(error))
                                }
                            } else {
                                do {
                                    progressSlider = audioManager.progress
                                    try audioManager.pauseAudio()
                                } catch let error {
                                    print(errorHandler(error))
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


