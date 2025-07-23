import AVFoundation

import AudioKit

import SwiftUI

// lets work on two visualizations: waveform and spectrogram

import Waveform

protocol VisualGraph: ObservableObject {
    // requires that any conforming class has this variable accessible and it is read-only as set is not used
    var rawData: [Any] { get }
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
    }

    func drawGraph(a: GraphicsContext, b: CGSize) {

    }

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

    }
}
