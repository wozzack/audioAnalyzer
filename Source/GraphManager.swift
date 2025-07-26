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

// will mutate graphics context
import Waveform

class GraphManager: ObservableObject {
    // how the fyuck to approach switching models?

    var visualModel: (any VisualGraph)?
    @Published var samples = visualModel.rawData?

    // needs to pass view to canvas

}
