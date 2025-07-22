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
    // use demo model for now
    var samples: SampleBuffer
    
    // for when empty, will mostly use for now
    
    init(file: AVAudioFile) {
        let stereo = file.floatChannelData()!
        samples = SampleBuffer(samples: stereo[0])
    }
    
}


