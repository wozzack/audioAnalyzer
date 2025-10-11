// pre-render with core graphics to UIImage for waveform via canvas
// ignore above, use canvas since core graphics requires a wrapper
// use accelerate framework with canvas or full metal for spectrogram test

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
    @MainActor func drawGraph(rect: CGRect, color: Color, lineWidth: CGFloat) throws -> CGImage
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
    @MainActor func drawGraph(rect: CGRect, color: Color, lineWidth: CGFloat) throws -> CGImage {
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
        let renderer = ImageRenderer(content: pathObject.stroke(color, lineWidth: lineWidth)
            .frame(width: rect.width, height: rect.height))
        
        guard let cgImage = renderer.cgImage else {
            throw GraphManagerError.GenericFailure(funcName: "drawGraph", reason: "failed to render waveform image")
        }
        return cgImage
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
    // freq and amp. [amp1, amp2, amp3, ...], timeSlice[freqBin]
    var spectrogramData: [[Float]] = [] // 2D array for time-frequency spectrogram
    var CGImageData: [SpectrogramCell]? = []
    
    // need to convert spectrogramData elements into spectrogram cells
    
    // create DFT per-frame inside frameDFT to avoid referencing undefined symbols and to keep type-checking simple
    
    struct SpectrogramCell {
        let x: CGFloat
        let y: CGFloat
        let color: Color
        let width: CGFloat
        let height: CGFloat
    }
    
    struct SpectrogramCanvas: View {
        let CGImageData: [SpectrogramCell]
        
        @ViewBuilder
        private func cellView(for cell: SpectrogramCell) -> some View {
            Rectangle()
                .fill(cell.color)
                .frame(width: cell.width, height: cell.height)
                .position(x: cell.x, y: cell.y)
        }
        
        var body: some View {
            ZStack {
                ForEach(CGImageData.indices, id: \ .self) { idx in
                    cellView(for: CGImageData[idx])
                }
            }
        }
    }
    
    // returns RGB values for blue > red > green for a given intensity value
    
    // buffers are lower level vs arrays and is a contiguoous block of memory, can be managed manually via pointers and UnsafeBufferPointer. convert array into buffer via array.withUnsafeBufferMutableBufferPointer. useful in audio cause easier and faster to access for realtime processing
    
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
            try fileDFT(frameSize: 1024, hopSize: 512)
            try convertToImageData()
            
                    
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
            
            // here lies our dear spectrogramData
            self.spectrogramData.append(freqFrame)
        }
    }
    // takes a buffer and does DFT on it to convert to frequency domain
    func frameDFT(timeFrame: [Float]) throws -> [Float] {
        // apply Hann window
        let hannWindow = vDSP.window(ofType: Float.self,
                                     usingSequence: .hanningDenormalized,
                                     count: timeFrame.count,
                                     isHalfWindow: false)
        let windowedData = vDSP.multiply(timeFrame, hannWindow)

        // prepare imaginary input
        let imaginary = [Float](repeating: 0, count: timeFrame.count)

        // create DFT for this frame size (explicit to help compiler)
        let dft = try vDSP.DiscreteFourierTransform(previous: nil,
                                                   count: timeFrame.count,
                                                   direction: .forward,
                                                   transformType: .complexComplex,
                                                   ofType: Float.self)

        // perform transform and break into explicit sub-expressions
        let transformed = dft.transform(real: windowedData, imaginary: imaginary)
        let realPart = transformed.0
        let imagPart = transformed.1
        
        // wtf am i doing with my life ******************************************
        var magnitude = [Float]()
        magnitude.reserveCapacity(realPart.count)
        for i in 0..<realPart.count {
            let r = realPart[i]
            let im = imagPart[i]
            magnitude.append(sqrt(r * r + im * im))
        }
        return magnitude
    }
    // an array of arrays, where the outer dimension are time slices and each inner array is divided into freq bins, and the
    // value in each bin represents the magnitude/amplitude
    
    func colorMapping(ampValue: Float, colorIndex: Int) throws -> Color {
            // so first bin will have value [0.0/31.0], looking like [[0.0/31,0], [1.0/31.0], [2.0/31.0], ...] in its entirety
        let colorBins = 32 // design choice
        let normalizedValue = CGFloat(colorIndex) / CGFloat(colorBins - 1)
        let startHue: CGFloat = (240.0/360.0) // blue hsv
        let hue = startHue - (startHue * normalizedValue) // 1.0 = red, 0.5 = green, 0.0 = blue
        let brightness = sqrt(normalizedValue)
        let saturation = log(1 + normalizedValue - 0.5) * 2
        
        let color = Color(hue: hue, saturation: saturation, brightness: brightness)
        return color
    }
    
    // puts extra layer of abstraction and normalizes the values, use for actual CGImage
    func convertToImageData() throws {
        let freqBins = CGFloat(self.spectrogramData[0].count)
        let timeSlices = CGFloat(self.spectrogramData.count)
        let colorBins = 32 // design decision
        let maxAmpValue = spectrogramData.flatMap { $0 }.max() ?? 0
        for (timeIndex, timeSlice) in self.spectrogramData.enumerated() {
            // freq and amp. [amp1, amp2, amp3, ...] = timeSlice[timeIndex][freqIndex], so timeSlice[N] would be made of N amplitude bins that are contained in the time duration of timeSlice, where N is the indexing of the timeslice
            for (freqIndex, ampValue) in timeSlice.enumerated() {
                let hSteps = self.shapeSize.height / freqBins
                let wSteps = self.shapeSize.width / timeSlices // should be deltaTime we are calculating
                let yNorm = CGFloat(freqIndex) * hSteps
                let xNorm = CGFloat(timeIndex) * wSteps
                // spectrogramData = [[...],...,[...]]
                // spectrogramData[timeIndex] = [amp1, amp2, ..., ampN] = timeSlice
                // spectrogramData[timeIndex][freqIndex] = amp = ampValue
                do {
                    let normAmpValue = ampValue / maxAmpValue
                    let colorIndex = min(max(Int(normAmpValue * Float(colorBins - 1)), 0), colorBins - 1)
                    let color = try colorMapping(ampValue: ampValue, colorIndex: colorIndex)
                    let cellWidth = self.shapeSize.width / CGFloat(timeSlices)
                    let cellHeight = self.shapeSize.height / CGFloat(freqBins)
                    let spectra = SpectrogramCell(x: xNorm, y: yNorm, color: color, width: cellWidth, height: cellHeight)
                    self.CGImageData?.append(spectra)
                } catch {
                    throw GraphManagerError.GenericFailure(funcName: "convertToImageData", reason: "failure to color map")
                }
            }
        }
        print("reached end of convertToImageData")
    }
    
    @MainActor func drawGraph(rect: CGRect, color: Color, lineWidth: CGFloat) throws -> CGImage {
         guard let CGImageData = self.CGImageData
         else {
             throw GraphManagerError.GenericFailure(funcName: "drawGraph", reason: "CGImageData is nil when trying to draw graph")
         }
         let canvasImage = SpectrogramCanvas(CGImageData: CGImageData)
         let renderer = ImageRenderer(content: canvasImage)
        
        guard let cgImage = renderer.cgImage else {
            throw GraphManagerError.GenericFailure(funcName: "drawGraph", reason: "failed to render spectrogram cgImage")
        }
        return cgImage
     }
    
    func drawGraph2(rect: CGRect, color: Color, lineWidth: CGFloat) throws -> CGImage {
        // created once actually called, implies spectrogram data exists at this point due to control flow
        lazy var timeSlices = spectrogramData.count
        lazy var freqBins = spectrogramData[0].count
        
        var rgbImageFormat = vImage_CGImageFormat(
            bitsPerComponent: 32,
            bitsPerPixel: 32 * 3,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: kCGBitmapByteOrder32Host.rawValue |
                CGBitmapInfo.floatComponents.rawValue |
                CGImageAlphaInfo.none.rawValue))!
        
        // creates a pixelbuffer representing an image for each RGB channel, and then creating the final buffer when interleaved
        let redBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: timeSlices, height: freqBins)
        let greenBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: timeSlices, height: freqBins)
        let blueBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: timeSlices, height: freqBins)
        let rgbBuffer = vImage.PixelBuffer<vImage.InterleavedFx3>(width: timeSlices, height: freqBins)
        
        // converts spectrogramData from an array to an unsafeMutableBufferPointer (has count, type, memory address, and built in bounds checking
        let freqValues: () = self.spectrogramData.withUnsafeMutableBufferPointer { unsafeBufferPointer in
            let freqBins = self.spectrogramData[0].count
            let timeSlices = self.spectrogramData.count
            let imageBuffer = vImage.PixelBuffer(
                data: unsafeBufferPointer.baseAddress!,
                width: timeSlices,
                height: freqBins,
                byteCountPerRow: timeSlices * MemoryLayout<Float>.stride,
                pixelFormat: vImage.PlanarF.self)
            
            SpectrogramView.multidimensionalLookupTable.apply(
                sources: [imageBuffer],
                destinations: [redBuffer, greenBuffer, blueBuffer],
                interpolation: .half)
            
            rgbBuffer.interleave(planarSourceBuffers: [redBuffer, greenBuffer, blueBuffer])
        }
        guard let cgImage = rgbBuffer.makeCGImage(cgImageFormat: rgbImageFormat) else {
            throw GraphManagerError.GenericFailure(funcName: "drawGraph2", reason: "failed to create CGImage from rgbBuffer")
        }
        return cgImage // ?? SpectrogramView.emptyCGImage
     }
    
    static var multidimensionalLookupTable: vImage.MultidimensionalLookupTable = {
        let amplitudeBins = UInt8(32) // divide all amplitude values into 32 bins for individual coloring
        let inputChannels = 1 // floats of intensity values
        let outputChannels = 3 // RGB output
        let lookupElements = Int(pow(Float(amplitudeBins), Float(inputChannels))) * Int(outputChannels)
        
        // allocates memory for an array of 16bit unsigned floats (0-65535) without auto-initializing default values, gives us access to buffer and count variable in closure. once all memory is given a value, it will be fully initialized
        let colorData = [UInt16](unsafeUninitializedCapacity: lookupElements) { buffer, count in
            // applied as multipier to RGB values
            let multiplier = CGFloat(UInt16.max)
            // for when we assign RGB values to buffer
            var bufferIndex = 0
            
            // code to determine Color properties for each amplitude bin
            for binIndex in ( 0 ..< amplitudeBins) {
                // so first bin will have value [0.0/31.0], looking like [[0.0/31,0], [1.0/31.0], [2.0/31.0], ...] in its entirety
                let normalizedValue = CGFloat(binIndex) / CGFloat(amplitudeBins - 1)
                let startHue: CGFloat = (240.0/360.0) // blue hsv
                let hue = startHue - (startHue * normalizedValue) // 1.0 = red, 0.5 = green, 0.0 = blue
                // to determine brightness
                let brightness = sqrt(normalizedValue)
                // to determine saturation
                let saturation = log(1 + normalizedValue - 0.5) * 2
               
                
                let color = Color(hue: hue, saturation: saturation, brightness: brightness)
                // gives context to what environment it will be rendered in, this case just being the default values
                let environment = EnvironmentValues()
                let resolvedColors = color.resolve(in: environment)
                
                let redHue = resolvedColors.red
                let greenHue = resolvedColors.green
                let blueHue = resolvedColors.blue
                
                // convert color values (0.0 - 1.0) tp UInt16(0 - 65535) and store in buffer
                buffer[ bufferIndex ] = UInt16(greenHue * Float(multiplier))
                bufferIndex += 1
                buffer[ bufferIndex ] = UInt16(redHue * Float(multiplier))
                bufferIndex += 1
                buffer[ bufferIndex ] = UInt16(blueHue * Float(multiplier))
                bufferIndex += 1
            }
            count = lookupElements
        }
        
        // expands for each channel used
        let entryCountPerSourceChannel = [UInt8](repeating: amplitudeBins,
                                                 count: inputChannels)
        
        //
        return vImage.MultidimensionalLookupTable(entryCountPerSourceChannel: entryCountPerSourceChannel,
                                                  destinationChannelCount: outputChannels,
                                                  data: colorData)
    }()
}

