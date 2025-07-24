/*
 Handles the loading of what type of infographic is shown.
 Currently thinking of spectrogram, waveform (amplitude), frequency spectrum, loudness meter, pitch tracking, chromagram, and MFCCs (spectral enevelope)
 */
// implement for both NSView (macOS) and UIView (iOS), try extension, composition/wrapping, and subclassing methods for practice when 
// implementing your own waveform model class. structure would probably be each 
// visualization is its own class, and graph manager handles the type of visual that 
// is showing (through general canvas?)

import AVFoundation
import SwiftUI
import AudioKit
import Waveform
import Foundation

class GraphManager: ObservableObject {
    // allows dynamic changes
    var visualModel: (any VisualGraph)?
    WaveformView.drawGraph(a: GraphicsContext, b: CGSize)

}
