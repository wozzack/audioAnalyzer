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
    
    var spectrogramData: [[Float]] = [] // 2D array for time-frequency spectrogram
    var imageData: [SpectrogramCell] = []
    
    // need to convert spectrogramData elements into spectrogram cells
    struct SpectrogramCell {
        let x: CGFloat
        let y: CGFloat
        let color: Color
        let width: CGFloat
        let height: CGFloat
    }
    
    // frameLength = number of audio frames stored in the buffer (data quantity)
    // frameSize = number of samples chosen per frame (usually fixed value, analysis choice)
    // audioframe = one sample per channel at a given point in time (so could have N values with N channels)
    // if buffer.frameLength < frameSize, dont have enough samples and must accumulate across multiple buffers until frameSize is reached. frameSize samples is what we use to actually do the FFT
    
    
    // processes buffers and stores in dsData
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
            
            // an array of floats representing magnitude
            self.dsData = samples
                    
        } else {
            throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "AVFile passed to processAudio does not match the AVFile stored in the WaveformView instance")
        }
    }
    // takes dsData as input and outputs frequency-domain converted dsData, calls on bufferDFT multiple times. need to append results of bufferDFT() to the frequency-domain value address
    func fileDFT(frameSize: Int, hopSize: Int) throws {
        guard let dsData = self.dsData
        else {
            throw GraphManagerError.GenericFailure(funcName: "fileDFT", reason: "dsData does not exist")
        }
        var bufferIndex = 0
        while bufferIndex + frameSize <= dsData.count {
            let timeFrame: [Float] = Array(dsData[bufferIndex..<(bufferIndex + frameSize)])
            guard let freqFrame = try? frameDFT(timeFrame: timeFrame)
            else {
                throw GraphManagerError.GenericFailure(funcName: "fileDFT", reason: "failed to create frequency frame")
            }
            self.spectrogramData.append(freqFrame)
            bufferIndex = bufferIndex + hopSize
        }
        if bufferIndex <= dsData.count {
            var timeFrame: [Float] = Array(dsData[bufferIndex..<(dsData.count)])
            let paddingFrame: [Float] = Array(repeating: (0.0), count: frameSize - (dsData.count - bufferIndex))
            timeFrame.append(contentsOf: paddingFrame)
            guard let freqFrame = try? frameDFT(timeFrame: timeFrame)
            else {
                throw GraphManagerError.GenericFailure(funcName: "fileDFT", reason: "failed to create frequency frame")
            }
            self.spectrogramData.append(freqFrame)
        }
    }
    // takes a buffer and does DFT on it to convert to frequency domain
    func frameDFT(timeFrame: [Float]) throws -> [Float] {
        let hannWindow = vDSP.window(ofType: Float.self,
                                     usingSequence: .hanningDenormalized,
                                     count: timeFrame.count,
                                     isHalfWindow: false)
        let windowedData = vDSP.multiply(timeFrame, hannWindow)
        let forwardDFT = try vDSP.DiscreteFourierTransform(previous: nil, count: timeFrame.count, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        let imaginary = [Float](repeating: 0, count: timeFrame.count)
        let (r, i) = forwardDFT.transform(real: windowedData, imaginary: imaginary)
        let magnitude = zip(r, i).map { sqrt($0 * $0 + $1 * $1) }
        print(magnitude)
        return magnitude
    }
    // an array of arrays, where the outer dimension are time slices and each inner array is divided into freq bins, and the
    // value in each bin represents the magnitude/amplitude
    
    func convertToImageData() {
        let freqBins = CGFloat(self.spectrogramData[0].count)
        let timeSlices = CGFloat(self.spectrogramData.count)
        for (timeIndex, timeSlice) in self.spectrogramData.enumerated() {
            
            // freq and amp. [amp1, amp2, amp3, ...], timeSlice[freqBin]
            for (freqIndex, freqBin) in timeSlice.enumerated() {
                let hSteps = self.shapeSize.height / freqBins
                let wSteps = self.shapeSize.width / timeSlices // should be deltaTime we are calculating
                let yNorm = CGFloat(freqBin) * hSteps
                let xNorm = CGFloat(timeIndex) * wSteps
                
                let spectra = SpectrogramCell(x: xNorm, y: yNorm, color: Color(.red), width: 1, height: 1)
                self.imageData.append(spectra)
            }
            
        }
    }
    
    func colorMapping(cell: SpectrogramCell) {
        
    }
    
    static var multidimensionalLookupTable: vImage.MultidimensionalLookupTable = {
        let amplitudeBins = UInt8(32)
        let inputChannels = 1 // floats of intensity values
        let outputChannels = 3 // RGB output
        let lookupElements = Int(pow(Float(amplitudeBins),
                                              Float(inputChannels))) * Int(outputChannels)
        
        let colorData = [UInt16](unsafeUninitializedCapacity: lookupElements) { buffer, count in
            let multiplier = CGFloat(UInt16.max)
            var bufferIndex = 0
            
            for binIndex in ( 0 ..< amplitudeBins) {
                // code to determine hue
                let normalizedValue = CGFloat(binIndex) / CGFloat(amplitudeBins - 1) // ranges from 0 to 1
                let startHue: CGFloat = (240.0/360.0) // blue hsv
                let hue = startHue - (startHue * normalizedValue) // 1.0 = red, 0.5 = green, 0.0 = blue
                // to determine brightness
                let brightness = sqrt(normalizedValue)
                // to determine saturation
                let saturation = log(1 + normalizedValue - 0.5) * 2
               
                
                let color = Color(hue: hue, saturation: saturation, brightness: brightness)
                let environment = EnvironmentValues()
                let resolvedColors = color.resolve(in: environment)
                
                let redHue = resolvedColors.red
                let greenHue = resolvedColors.green
                let blueHue = resolvedColors.blue
                
                // what does this do
                buffer[ bufferIndex ] = UInt16(greenHue * Float(multiplier))
                bufferIndex += 1
                buffer[ bufferIndex ] = UInt16(redHue * Float(multiplier))
                bufferIndex += 1
                buffer[ bufferIndex ] = UInt16(blueHue * Float(multiplier))
                bufferIndex += 1
            }
            
            count = lookupElements
        }
        
        let entryCountPerSourceChannel = [UInt8](repeating: amplitudeBins,
                                                 count: inputChannels)
        
        return vImage.MultidimensionalLookupTable(entryCountPerSourceChannel: entryCountPerSourceChannel,
                                                  destinationChannelCount: outputChannels,
                                                  data: colorData)
    }()
    
    
    func drawSpectrogram() throws -> CGImage {
        
        let freqValues = self.spectrogramData.withUnsafeMutableBufferPointer {
            let freqBins = self.spectrogramData[0].count
            let timeSlices = self.spectrogramData.count
            let planarImageBuffer = vImage.PixelBuffer(
                data: $0.baseAddress!,
                width: freqBins,
                height: timeSlices,
                byteCountPerRow: freqBins * MemoryLayout<Float>.stride,
                pixelFormat: vImage.PlanarF.self)
            
    }
    
    // we dont want this to return path object, better to use canvas directly
    func drawGraph(rect: CGRect) throws -> Path {
        
        return Path()
    }
}

