// pre-render with core graphics to UIImage for waveform via canvas
// ignore above, use canvas since core graphics requires a wrapper
// use accelerate framework with canvas or full metal for spectrogram

import AVFoundation

import AudioKit

import SwiftUI

import Waveform

import Accelerate

protocol VisualGraph: ObservableObject, AnyObject {
    associatedtype DSType
    // requires that any conforming class has this variable accessible and it is read-only as set is not used
    var graphType: GraphType { get }
    // raw data is used to draw the graph, needs to be processed before drawing
    var rawData: [Any]? { get }
    var dsData: DSType? { get }
    var shapeSize: CGRect { get set }
    func processAudio(AVFile: AVAudioFile) throws
    // canvas stuff
    func drawGraph(rect: CGRect) throws -> Path
}
class WaveformView: VisualGraph, ObservableObject {
    // just two dimensional data, amplitude and time, need to handle downsampling
    typealias DSType = [(Float, Float)]
    var rawData: [Any]? = []
    var dsData: DSType? = []
    var shapeSize = CGRect(x: 0, y: 0, width: 300, height: 600)
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
            throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "AVFile passed to processAudio does not match the AVFile stored in the WaveformView instance")
        }
    }
    // check for cgrect size, dsData existance,
    func drawGraph(rect: CGRect) throws -> Path {
        var pathObject = Path()
        var unitTestPath: [(CGFloat, CGFloat, CGFloat)] = []
        guard let dsData = self.dsData
        else {
            throw GraphManagerError.GenericFailure(funcName: "drawGraph", reason: "dsData is nil when trying to draw graph")
        }
        // print("Current dsData: \(dsData)")
        for (i, data) in dsData.enumerated() {
            let normX = rect.origin.x + CGFloat(i) / CGFloat(max(dsData.count - 1, 1)) * rect.width
            let minY = rect.midY - CGFloat(data.0) * rect.height / 2
            let maxY = rect.midY - CGFloat(data.1) * rect.height / 2
            
            // for unit test
            unitTestPath.append((normX, minY, maxY))
            
            pathObject.move(to: CGPoint(x: normX, y: minY))
            pathObject.addLine(to: CGPoint(x: normX, y: maxY))
        }
        return pathObject
    }
}

class SpectrogramView: VisualGraph, ObservableObject {
    // time, frequency, color (amplitude)
    typealias DSType = [Float]
    var rawData: [Any]? = []
    var dsData: DSType? = []
    var shapeSize = CGRect(x: 0, y: 0, width: 300, height: 600)
    var AVFile: AVAudioFile?
    var graphType: GraphType = .spectrogram
    
    var freqData = [Float](repeating: 0, count: 2048) // 2048 is holder value for now
    // frameLength = number of audio frames stored in the buffer (data quantity)
    // frameSize = number of samples chosen per frame (usually fixed value, analysis choice)
    // audioframe = one sample per channel at a given point in time (so could have N values with N channels)
    // if buffer.frameLength < frameSize, dont have enough samples and must accumulate across multiple buffers until frameSize is reached. frameSize samples is what we use to actually do the FFT
    
    func processAudio(AVFile: AVAudioFile) throws {
        // implement spectrogram processing
        if AVFile == AVFile {
            guard let buffer = try AVAudioPCMBuffer(file: AVAudioFile(forReading: AVFile.url)),
                    buffer.floatChannelData != nil,
                    buffer.frameLength > 0
            else {
                throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "failure to properly allocate PCM buffer")
            }
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
            let length = Int(self.shapeSize.width)
            
            //for remaining fraction samples that can be accounted for by adding one more sample
            let totalSamples = Int(buffer.frameLength) / length + (Int(buffer.frameLength) % length == 0 ? 0 : 1)
            let channelCount = Int(buffer.format.channelCount)
            var samples: [Float] = Array(repeating: (0.0), count: totalSamples)
            for channel in 0..<channelCount {
                let channelData = Array(UnsafeBufferPointer(
                    start: buffer.floatChannelData?[channel],
                    count: Int(buffer.frameLength)))
                samples.append(contentsOf: channelData)
            }
            
            // an array of floats
            self.dsData = samples
                    
        } else {
            throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "AVFile passed to processAudio does not match the AVFile stored in the WaveformView instance")
        }
    }
    
    // takes dsData and does DFT on it to convert to frequency domain
    func DFT(timeData: [Float]) throws {
        var frequencyData = [Float](repeating: 0, count: timeData.count)
        let hannWindow = vDSP.window(ofType: Float.self,
                                     usingSequence: .hanningDenormalized,
                                     count: timeData.count,
                                     isHalfWindow: false)
        let windowedData = vDSP.multiply(timeData, hannWindow)
        
        // so we need a way to make sure we are feeding frameSize samples into this function
        let forwardDFT = try? vDSP.DiscreteFourierTransform(previous: nil, count: timeData.count, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        
        let imaginary = [Float](repeating: 0, count: self.dsData!.count)
        // remember, this processes a buffer at a time
        // this gives the real and imaginary components from the input time domain, find the norm of both to get magnitude
        let (r, i) = forwardDFT!.transform(real: self.dsData!, imaginary: imaginary)
        self.freqData = zip(r, i).map {
            sqrt($0 * $0 + $1 * $1)
        }
    }
    // an array of arrays, where the outer dimension are time slices and each inner array is divided into freq bins, and the
    // value in each bin represents the magnitude/amplitude
    
    func drawGraph(rect: CGRect) throws -> Path {
        
        return Path()
    }
}
