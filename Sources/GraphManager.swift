/*
 Handles the loading of what type of infographic is shown.
 Currently thinking of spectrogram, waveform (amplitude), frequency spectrum, loudness meter, pitch tracking, chromagram, and MFCCs (spectral enevelope)
 */
// implement for both NSView (macOS) and UIView (iOS), try extension, composition/wrapping, and subclassing methods for practice when
// implementing your own waveform model class. structure would probably be each
// visualization is its own class, and graph manager handles the type of visual that
// is showing (through general canvas?)

// this should handle all adjustments to the graphview such as zoom, switching models, etc

import AVFoundation

import AudioKit

import Foundation

import SwiftUI

enum GraphType: VisualGraph {
    case Waveform
    case Spectrogram
}


class GraphManager: ObservableObject {
    // handles graph loading/changing and graph view modification

    @Published var visualModel: (any VisualGraph)?
    @Published var samples = visualModel.rawData?
    @Published var graphColor: Color?
    @Published var graphShowing: Boolean = false
    
    
    func changeGraph(to newGraph: VisualGraph, with file: AVAudioFile) throws {
        clearGraph()
        switch graph {
        case .Waveform:
            let model = WaveformView()
            self.visualModel = model
            self.samples = processAudio(AVFile: file)
            self.graphShowing = true
        
        case .Spectrogram:
            // todo
    
    }
    
    // maybe have a placeholder text to inform graph needs to be loaded
    func clearGraph() throws {
        visualModel = nil
        samples = nil
        graphColor = nil
        graphShowing = true
    }
    
    func changeGraphColor(color: Color) throws {
        
    }

    // needs to pass view to canvas

}
