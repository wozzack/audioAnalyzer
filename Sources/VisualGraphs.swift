// pre-render with core graphics to UIImage for waveform via canvas
// ignore above, use canvas since core graphics requires a wrapper
// use accelerate framework with canvas or full metal for spectrogram

import AVFoundation

import AudioKit

import SwiftUI

import Waveform


protocol VisualGraph: ObservableObject, AnyObject {
    associatedtype DSType
    // requires that any conforming class has this variable accessible and it is read-only as set is not used
    var graphType: GraphType { get }
    // raw data is used to draw the graph, needs to be processed before drawing
    var rawData: [Any]? { get }
    var dsData: [(Float, Float)]? { get }
    func processAudio(AVFile: AVAudioFile) throws
    // canvas stuff
    func drawGraph(rect: CGRect) throws -> Path
}
class WaveformView: VisualGraph, ObservableObject {
    // just two dimensional data, amplitude and time, need to handle downsampling
    typealias DSType = [(Float, Float)]
    var rawData: [Any]? = []
    var dsData: DSType? = []
    // unneeded just do in drawGraph
    // var shapeData: [CGPoint]?
    // need to convert to CGPoints
    var AVFile: AVAudioFile?
    var graphType: GraphType = .waveform
    
    // traditionally we would make this min/max and display as an float array of pairs
    // but we can also use a single float array and average the samples
    
    // creates shapeData [CGPoint]
    
    init() { }

    // need to handle shapeData
    func processAudio(AVFile: AVAudioFile) throws {
        if AVFile == AVFile {
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
            self.dsData = try minmaxDownSampling(length: 300, file: AVFile)
        } else {
            throw VisualGraphError.GenericFailure(funcName: "processAudio")
        }
    }

    func drawGraph(rect: CGRect) throws -> Path {
        var pathObject = Path()
        guard let dsData = self.dsData
        else {
            throw VisualGraphError.GenericFailure(funcName: "drawGraph guard dsData")
        }
        // print("Current dsData: \(dsData)")
        for (i, data) in dsData.enumerated() {
            let normX = rect.origin.x + CGFloat(i) / CGFloat(max(dsData.count - 1, 1)) * rect.width
            let minY = rect.midY - CGFloat(data.0) * rect.height / 2
            let maxY = rect.midY - CGFloat(data.1) * rect.height / 2
            pathObject.move(to: CGPoint(x: normX, y: minY))
            pathObject.addLine(to: CGPoint(x: normX, y: maxY))
        }
        return pathObject
    }
}

class SpectrogramView: VisualGraph, ObservableObject {
    // time, frequency, color (amplitude)
    typealias DSType = [(Float, Float, Color)]
    var rawData: [Any]? = []
    var dsData: [(Float, Float)]? = []
    var AVFile: AVAudioFile?
    var graphType: GraphType = .spectrogram
    
    func processAudio(AVFile: AVAudioFile) throws {
        // implement spectrogram processing
    }
    
    func drawGraph(rect: CGRect) throws -> Path {
        return Path()
    }
}
