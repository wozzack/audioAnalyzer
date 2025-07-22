import SwiftUI
import AVFoundation
import AudioKit
import Waveform

// lets work on two visualizations: waveform and spectrogram

protocol VisualGraph: ObservableObject {
    // requires that any conforming class has this variable accessible and it is read-only as set is not used
    var rawData: [Any] { get }
    // returns what?....
    func processAudio(file: AVAudioFile)
    // canvas stuff
    func drawGraph(a: GraphicsContext, b: CGSize)
}

class WaveformView: VisualGraph, ObservableObject {
    var rawData: [Any]
    
    init(file: AVAudioFile) {
        if file == file {
            self.rawData = [file.floatChannelData() as Any]
        } else {
            self.rawData = []
        }
    }
    
    func processAudio(file: AVAudioFile) {
        
    }
    
    func drawGraph(a: GraphicsContext, b: CGSize) {
        
    }
    
}

class SpectrogramView: VisualGraph, ObservableObject {
    var rawData: [Any]
    
    init(file: AVAudioFile) {
        if file == file {
            self.rawData = [file.floatChannelData() as Any]
        } else {
            self.rawData = []
        }
    }
    
    func processAudio(file: AVAudioFile) {
        
    }
    
    func drawGraph(a: GraphicsContext, b: CGSize) {
        
    }
}

