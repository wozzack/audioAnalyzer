import AVFoundation
import AudioKit
import SwiftUI

struct ContentView: View {

    @StateObject var audioManager = AudioManager()
    @StateObject var waveformGraph = WaveformGraph()
    @StateObject var canvasManager = CanvasManager()
    @ObservedObject var micManager: MicManager
    @StateObject var errorReporter = ErrorReporter()
    
    init(micManager: MicManager) {
        self.micManager = micManager
    }

    @State var song: String = "misato.mp3"
    @State var isPlaylistShowing: Bool = false
    @State var progressSlider: Double = 0.0
    @State var amplitudeLevel: Float = 0.0
    // spectrogram display controls
    @State var freqScale: FrequencyScale = .mel
    @State var orientation: SpectrogramOrientation = .horizontal
    @State var displayMode: DisplayMode = .spectrogram

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack {
                HStack {
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
                                errorReporter.report(error)
                            }
                        }
                        .foregroundColor(.blue)
                    
                    Button("Add Song") {
                        do {
                            let audio = try convertToAudioObject(s: song)
                            try audioManager.addToPlaylist(audio: audio)
                            song = ""
                        } catch let error {
                            errorReporter.report(error)
                        }
                    }
                    .padding(10)
                }
                
                Text("Playlist")
                    .frame(width: 175, height: 25)
                    .border(Color(.red))
                
                ScrollView {
                    VStack {
                        ForEach(audioManager.playlist, id: \.self) { audioFile in
                            Button {
                                do {
                                    try audioManager.loadAudio(audio: audioFile)
                                    // loadAudio sets audioManager.player.file to be the current file we need
                                    try canvasManager.changeGraph(newGraph: .spectrogram, file: audioManager.player.file!)
                                    // try canvasManager.visualModel?.processAudio(AVFile: audioManager.player.file!)
                                    audioManager.isLoaded = true
                                } catch let error {
                                    errorReporter.report(error)
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
                
                Button("Clear playlist.") {
                    audioManager.clearPlaylist()
                }
            }
            
            .frame(width: 200)
            .padding(.vertical, 10)
            .border(Color(.orange))

            VStack(spacing: 12) {
                GraphView(
                    model: canvasManager.visualModel as? SpectrogramGraph,
                    displayMode: displayMode,
                    orientation: orientation,
                    isLive: canvasManager.isLive,
                    showContent: audioManager.player.file != nil && audioManager.isLoaded,
                    placeholder: "\(micManager.ampLevel)"
                )
                .frame(width: 600, height: 300)
                .border(Color(.blue))
                .padding(10)

                // view mode: spectrogram / spectrum / LTAS
                Picker("View", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 600)
                .padding(.horizontal, 10)

                // spectrogram display controls
                HStack {
                    Picker("Scale", selection: $freqScale) {
                        ForEach(FrequencyScale.allCases) { scale in
                            Text(scale.label).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: freqScale) { _, newValue in
                        canvasManager.setFrequencyScale(newValue)
                    }

                    Picker("Orientation", selection: $orientation) {
                        ForEach(SpectrogramOrientation.allCases) { o in
                            Text(o.label).tag(o)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(width: 600)
                .padding(.horizontal, 10)
                
                Button(canvasManager.isLive ? "Stop Live" : "Go Live") {
                    Task {
                        do {
                            if canvasManager.isLive {
                                canvasManager.stopLive()
                                micManager.stopRecording()
                            } else {
                                try await micManager.startRecording()
                                let sampleRate = micManager.engine.inputNode.outputFormat(forBus: 0).sampleRate
                                canvasManager.startLive(mic: micManager, sampleRate: sampleRate)
                            }
                        } catch let error {
                            errorReporter.report(error)
                        }
                    }
                }
                .padding(10)
                HStack {
                    Button(audioManager.isPlaying ? "Pause" : "Play") {
                        do {
                            if audioManager.player.isPlaying {
                                try audioManager.pauseAudio()
                            } else {
                                try audioManager.playAudio()
                            }
                        } catch let error {
                            errorReporter.report(error)
                        }
                    }
                    .padding(10)
                    Text("\(audioManager.player.currentTime, specifier: "%.1f")")

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
                                    errorReporter.report(error)
                                }
                            } else {
                                do {
                                    progressSlider = audioManager.progress
                                    try audioManager.pauseAudio()
                                } catch let error {
                                    errorReporter.report(error)
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
            .frame(width: 640)
            .padding(.vertical, 10)
            .border(Color(.orange))
        }
        .padding(20)
        .alert(item: $errorReporter.currentError) { presented in
            Alert(
                title: Text("Error"),
                message: Text(presented.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

#Preview {
    ContentView(micManager: MicManager(
        outputURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview.caf")))
}
