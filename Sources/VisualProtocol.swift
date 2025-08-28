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
    var dsData: [(Float, Float)]? { get }
    func processAudio(AVFile: AVAudioFile) throws
    // canvas stuff
    func drawGraph(rect: CGRect) throws -> Path
}
class WaveformView: VisualGraph, ObservableObject {
    // just two dimensional data, amplitude and time, need to handle downsampling
    var rawData: [Any]? = []
    var dsData: [(Float, Float)]? = []
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
        print("Reached processAudio...")
        if AVFile == AVFile {
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
            self.dsData = try minmaxDownSampling(length: 300, file: AVFile)
        } else {
            throw VisualGraphError.GenericFailure(funcName: "processAudio")
        }
    }
    
    // requires shapeData to be set

    func drawGraph(rect: CGRect) throws -> Path {
        print("Reached drawGraph...")
        var pathObject = Path()
        guard let dsData = self.dsData
        else {
            print("FAILURE at dsData check")
            return pathObject
        }
        print("Current dsData: \(dsData)")
        let dummyMinMaxData: [(Float, Float)] = (0..<50).map { i in
            let x = Float(i) / 50.0
            let minVal = sin(2 * .pi * x)
            let maxVal = minVal + 0.2 // offset for visualization
            return (minVal, maxVal)
        }
        for data in dummyMinMaxData {
            let normX = rect.origin.x + CGFloat(data.0) / CGFloat(max(dummyMinMaxData.count - 1, 1)) * rect.width
                    // Y: center and scale amplitude
                    let minY = rect.midY - CGFloat(data.0) * rect.height / 2
                    let maxY = rect.midY - CGFloat(data.1) * rect.height / 2
                    pathObject.move(to: CGPoint(x: normX, y: minY))
                    pathObject.addLine(to: CGPoint(x: normX, y: maxY))
        // for data in dsData {
            // convert CGPoint to normalized coordinates
            // shouldnt this be done in processAudio? no, as we can not assume the rect size
            // if let tuple = data as? (x: Float, y: Float) {
                // print("reached loop")
            /*
                let normX = rect.origin.x + CGFloat(data.0) * rect.width
                let normY = rect.origin.y + CGFloat(data.1) * rect.height
            
                let point = CGPoint(x: normX, y: normY)
                print(point)
                pathObject.addArc(center: point, radius: 1.0, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
             */
            }
        return pathObject
    }
}
