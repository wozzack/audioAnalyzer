/*
 Handles the loading of what type of infographic is shown.
 Currently thinking of spectrogram, waveform (amplitude), frequency spectrum, loudness meter, pitch tracking, chromagram, and MFCCs (spectral enevelope)
 */

import SwiftUI
import Waveform
import AVFoundation
import AudioKit

// implement for both NSView (macOS) and UIView (iOS), try extension, composition/wrapping, and subclassing methods for practice when implementing your own waveform model class. structure would probably be each visualization is its own class, and graph manager handles the type of visual that is showing (through general canvas?)


class GraphManager: ObservableObject {
    // allows dynamic changes
    var visualModel: (any VisualGraph)?
    
}


