// pre-render with core graphics to UIImage for waveform via canvas
// ignore above, use canvas since core graphics requires a wrapper
// use accelerate framework with canvas or full metal for spectrogram

import AVFoundation

import AudioKit

import SwiftUI

import Waveform


protocol VisualGraph: ObservableObject {
    // requires that any conforming class has this variable accessible and it is read-only as set is not used
    var graphType: GraphType { get }
    // raw data is used to draw the graph, needs to be processed before drawing
    var rawData: [Any]? { get }
    var samples: SampleBuffer? { get }
    func processAudio(AVFile: AVAudioFile) throws
    // canvas stuff
    func drawGraph(rect: CGRect) throws -> Path
}
class WaveformView: VisualGraph, ObservableObject {
    // just two dimensional data, amplitude and time, need to handle downsampling
    var rawData: [Any]? = []
    var samples: SampleBuffer?
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
            let sample = try minmaxDownSampling(length: 300, file: AVFile)
            self.samples = SampleBuffer(samples: sample)

        } else {
            throw VisualGraphError.GenericFailure(funcName: "processAudio")
        }
    }
    
    // requires shapeData to be set

    func drawGraph(rect: CGRect) throws -> Path {
        
        //guard let shapeData = self.shapeData
        //else {
            //throw VisualGraphError.GenericFailure(funcName: "drawGraph")
        //}
        var pathObject = Path()
        for data in samples {
            // convert CGPoint to normalized coordinates
            // shouldnt this be done in processAudio? no, as we can not assume the rect size
            let normX = rect.origin.x + data.x * rect.width
            let normY = rect.origin.y + data.y * rect.height
            let point = CGPoint(x: normX, y: normY)
            pathObject.addArc(center: point, radius: 1.0, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
        }
        return pathObject
    }  
}
