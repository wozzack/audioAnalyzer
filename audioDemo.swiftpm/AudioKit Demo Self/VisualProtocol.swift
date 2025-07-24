// pre-render with core graphics to UIImage for waveform via canvas
// ignore above, use canvas since core graphics requires a wrapper
// use accelerate framework with canvas or full metal for spectrogram

import AVFoundation

import AudioKit

import SwiftUI

import Waveform

protocol VisualGraph: ObservableObject {
    // requires that any conforming class has this variable accessible and it is read-only as set is not used
    var rawData: [Any] { get }
    var processedData: [Any] { get }
    // returns what?....
    func processAudio(AVFile: AVAudioFile) throws
    // canvas stuff
    func drawGraph(a: GraphicsContext, b: CGSize)
}
class WaveformView: VisualGraph, ObservableObject {
    // just two dimensional data, amplitude and time, need to handle downsampling
    var rawData: [Any] = []
    var samples: SampleBuffer?
    var AVFile: AVAudioFile?

    func processAudio(AVFile: AVAudioFile) throws {
        if AVFile == AVFile {
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
        } else {
            throw AudioManagerError.GenericFailure
        }
        let sample = genericDownSampling(length: 300, file: AVFile)
        self.samples = SampleBuffer(samples: sample)
    }
    
    // called in canvas as GraphManager.visualModel.drawGraph(start: 0, end: )
    func drawGraph(start: s, end: e) -> Waveform {
        var display = Waveform(
            samples: self.samples, 
            start: Int(s * Double(self.samples.count - 1),
            ))
        return display
            
    }
class SpectrogramView: VisualGraph, ObservableObject {
    // whatever
    var rawData: [Any]

    func processAudio(AVFile: AVAudioFile) throws {
        if AVFile == AVFile {
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
        } else {
            throw AudioManagerError.GenericFailure
        }
    }

    func drawGraph(a: GraphicsContext, b: CGSize) {
        // whatever we end up outputting here needs to be able to be handled
        // generically by the graphManager...
    }
}
