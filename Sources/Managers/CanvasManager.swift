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
    case unknown // Added for testing default case
}

class CanvasManager: ObservableObject {
    // handles graph loading/changing and graph view modification

    @Published var visualModel: (any VisualGraph)?
    //@Published var visualModel = WaveformView()
    @Published var graphColor: Color = .blue
    @Published var graphShowing: Bool = false
    
    // could change graph type or the audio file itself
    func changeGraph(newGraph: GraphType, file: AVAudioFile) throws {
        clearGraph()
        switch newGraph {
        case .waveform:
            do {
                let model = WaveformView()
                try model.processAudio(AVFile: file)
                self.visualModel = model
                self.graphShowing = true
            } catch {
                throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to process audio for waveform graph")
            }
        case .spectrogram:
            do {
                let model = SpectrogramView()
                try model.processAudio(AVFile: file)
                self.visualModel = model
                self.graphShowing = true
            } catch {
                throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to process audio for spectrogram graph")
            }
        @unknown default:
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "unsupported graph type")
        }
    }

    func clearGraph() {
        self.graphShowing = false
        self.visualModel = nil
    }
    
    func changeGraphColor(color: Color) {
        self.graphColor = color
    }
}
