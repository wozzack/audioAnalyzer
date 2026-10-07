import AVFoundation
import AudioKit
import SwiftUI

struct ContentView: View {

    @StateObject var audioManager = AudioManager()
    @StateObject var waveformView = WaveformView()
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

    // draws the spectrogram image into the canvas honoring the chosen orientation
    // orientation is same image data laid out differently
    private func drawSpectrogram(_ image: CGImage, in context: GraphicsContext, size: CGSize) {
        var ctx = context
        let img = Image(decorative: image, scale: 1)
        switch orientation {
        case .horizontal:
            ctx.draw(img, in: CGRect(origin: .zero, size: size))
        case .vertical:
            // rotate about center and draw into a swapped-dimension rect so the image
            // fills the frame
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .degrees(-90))
            ctx.draw(img, in: CGRect(x: -size.height / 2, y: -size.width / 2,
                                     width: size.height, height: size.width))
        }
    }

    var body: some View {
        HStack {
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
            
            .frame(width: 200, height: 450)
            .border(Color(.orange))

            VStack {
                Group {
                    if canvasManager.isLive {
                        // live mode: redraw on a timer so the scrolling spectrogram animates
                        // even though warpedData changes aren't observed by this view
                        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                            let tick = timeline.date
                            Canvas { context, size in
                                _ = tick
                                if let cgImage = (try? canvasManager.visualModel?.drawGraph(
                                    rect: CGRect(origin: .zero, size: size), color: Color(.red), lineWidth: 1.0)) ?? nil {
                                    drawSpectrogram(cgImage, in: context, size: size)
                                }
                            }
                        }
                    } else {
                        Canvas { context, size in
                            if let _ = audioManager.player.file, audioManager.isLoaded {
                                do {
                                    //  grabs raw data from the AVAudioFile and processes it via unique downsampling technique
                                    let cgImage = try canvasManager.visualModel?.drawGraph(rect: CGRect(origin: .zero, size: size), color: Color(.red), lineWidth: CGFloat(1.0)) // color actually doesnt do anything for spectrogram

                                    if let cgImage {
                                        drawSpectrogram(cgImage, in: context, size: size)
                                    }
                                } catch let error {
                                    errorReporter.report(error)
                                }
                            } else {
                                let placeholderText = Text("\(micManager.ampLevel)")
                                context.draw(placeholderText, at: CGPoint(x: size.width / 2, y: size.height / 2))
                            }
                        }
                        .onChange(of: audioManager.player.file) { _, newState in
                            // reruns canvas closure if loaded file is changed.
                        }
                    }
                }
                .frame(width: 600, height: 300)
                .border(Color(.blue))
                .padding(10)

                // Spectrogram display controls
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
            .frame(width: 650, height: 450)
            .border(Color(.orange))
        }
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
