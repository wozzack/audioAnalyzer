/*
 Handles the loading of what type of infographic is shown.
 Currently thinking of spectrogram, waveform (amplitude), frequency spectrum, loudness meter, pitch tracking, chromagram, and MFCCs (spectral enevelope)
 */
// implement for both NSView (macOS) and UIView (iOS), try extension, composition/wrapping, and subclassing methods for practice when
// implementing your own waveform model class. structure would probably be each
// visualization is its own class, and graph manager handles the type of visual that
// is showing (through general canvas?)

// this should handle all adjustments to the graphview such as zoom, switching models, etc

// im reading this waveform documentation and its confusing as fuck so i kinda have two choices
// 1. spend significant amount of time understanding the waveform class and see if i can modify the display color through an extension or some shit
// 2. create my own displayclass from scratch, which i already have to do for spectrogram anyways

import AVFoundation
import AudioKit
import Foundation
import SwiftUI

enum GraphType {
    case waveform
    case spectrogram
}

class CanvasManager: ObservableObject {
    // handles graph loading/changing and graph view modification
    @Published var visualModel: (any VisualGraph)?
    @Published var graphColor: Color = .blue
    @Published var graphShowing: Bool = false
    @Published var isLive: Bool = false

    // owns the live streaming engine while live mode is active
    private var streaming: StreamingManager?

    /*
     startLive: prompted from user action on button, initalizes everything that needs to be done plus flag setting. clears graph, initializes streaming manager and sets renderer (SpectrogramView). starts renderer and sets bool flags graphShowing and isLive
     @: called by ContentView; calls clearGraph() and start()
     needs: micManager, sampleRate
     gives: updated empty graph, StreamingManager, graphShowing and isLive flag update
     */
    func startLive(mic: MicManager, sampleRate: Double) {
        clearGraph()
        let engine = StreamingManager(source: mic)
        streaming = engine
        visualModel = engine.renderer
        engine.start(sampleRate: sampleRate)
        graphShowing = true
        isLive = true
    }
    /*
     stopLive: prompted from user action on button, deallocates StreamingManager plus sets flag setting. clears graph and sets bool flag isLive
     @: called by ContentView; calls stop()
     needs: nothing
     gives: updated empty graph, freed memory, isLive flag update
     */
    func stopLive() {
        streaming?.stop()
        streaming = nil
        isLive = false
        clearGraph()
    }
    /*
     changeGraph: changes graph type. clears graph and follows case logic, decides model view and processes the file accordingly. initializes visualModel and sets graphShowing flag
     @: called by ContentView; calls processFile()
     needs: new graphType, valid AVAudioFile
     gives: new visualModel and updated graphShowing flag
     */
    func changeGraph(newGraph: GraphType, file: AVAudioFile) throws {
        clearGraph()
        switch newGraph {
        case .waveform:
            do {
                let model = WaveformView() 
                try model.processFile(AVFile: file)
                self.visualModel = model
                self.graphShowing = true
            } catch {
                throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to process audio for waveform graph")
            }
        case .spectrogram:
            do {
                let model = SpectrogramView()
                try model.processFile(AVFile: file)
                //try model.fileDFT(frameSize: 2048, hopSize: 2)
                //try model.convertToImageData()
                self.visualModel = model
                self.graphShowing = true
            } catch {
                throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to process audio for spectrogram graph")
            }
        @unknown default:
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "unsupported graph type")
        }
    }

    /*
     setFrequencyScale: change the spectrogram frequency axis scale (log/mel/linear). checks if we are using live microphone input or processing from a file
     @: called by ContentView; calls setFrequencyScale() (the other one) and processFile()
     needs: frequency scale type
     gives: updated frequency scale and new graph scaling (visual)
     */
    func setFrequencyScale(_ scale: FrequencyScale) {
        if isLive, let streaming {
            streaming.setFrequencyScale(scale)
        } else if let spec = visualModel as? SpectrogramView, let file = spec.AVFile {
            spec.frequencyScale = scale
            try? spec.processFile(AVFile: file)
        }
    }
    /*
     clearGraph: clears graph, sets graphShowing flag to false and deallocates visualModel
     @: called by startLive(), stopLive(); calls nothing
     needs: nothing
     gives: freed memory, updated boolean flag
     */
    func clearGraph() {
        self.graphShowing = false
        self.visualModel = nil
    }
    
    /*
     changeGraphColor: changes graph color
     @: called by nothing; calls nothing
     needs: color
     gives: updated graphColor
     */
    func changeGraphColor(color: Color) {
        self.graphColor = color
    }
}
