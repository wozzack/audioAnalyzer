import AVFoundation
import AudioKit
import SwiftUI
import Waveform
import Accelerate
import os

protocol VisualGraph: ObservableObject, AnyObject {
    associatedtype DSType
    //guu requires that any conforming class has this variable accessible and it is read-only as set is not used
    var graphType: GraphType { get }
    // raw data is used to draw the graph, needs to be processed before drawing
    var rawData: [Any]? { get }
    var dsData: DSType? { get }
    func processFile(AVFile: AVAudioFile) throws
    // canvas stuff
    @MainActor func drawGraph(rect: CGRect, color: Color, lineWidth: CGFloat) throws -> CGImage
}

enum FrequencyScale: CaseIterable, Identifiable {
    case log
    case mel
    case linear
    var id: Self { self }
    var label: String {
        switch self {
        case .log: return "Log"
        case .mel: return "Mel"
        case .linear: return "Linear"
        }
    }
}

// how the finished spectrogram image is laid onto the canvas
enum SpectrogramOrientation: CaseIterable, Identifiable {
    case horizontal   // time flows left to right, frequency vertical
    case vertical     // time flows bottom to top, frequency horizontal
    var id: Self { self }
    var label: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

// which view of the same FFT data to show. all three derive from the caches the SpectrogramGraph already holds
enum DisplayMode: CaseIterable, Identifiable {
    case spectrogram   // full 2D image (time x frequency)
    case spectrum      // newest single column (1D)
    case ltas          // time-averaged spectrum (1D)
    var id: Self { self }
    var label: String {
        switch self {
        case .spectrogram: return "Spectrogram"
        case .spectrum: return "Spectrum"
        case .ltas: return "LTAS"
        }
    }
}

class WaveformGraph: VisualGraph, ObservableObject {
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
    // ranges: AVFile = any valid audio file; fills dsData with (min, max) sample pairs, each value in [-1.0, 1.0]
    func processFile(AVFile: AVAudioFile) throws {
        if AVFile == AVFile {
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
            self.dsData = try minmaxDownSampling(length: 300, file: AVFile)
        } else {
            throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "AVFile passed to processAudio does not match the AVFile stored in the WaveformGraph instance")
        }
    }
    // check for cgrect size, dsData existance,
    // ranges: rect = canvas rect in points (width/height > 0); lineWidth ≥ 0 pts; reads dsData pairs in [-1.0, 1.0]; returns a CGImage
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

struct SpectrogramConfig {
    var frameSize: Int = 2048 // fft analysis size
    var hopSize: Int = 512 // 75% coverage
    var minFrequency: Float = 40 //
    var outputBins: Int = 256 // number of frequency bins
    var rollingWidth: Int = 512 // for live mode
    var fileTargetColumns: Int = 512 // for file mode
    var floorDB: Float = -80 // default values
    var ceilingDB: Float = 0
}

class SpectrogramGraph: VisualGraph, ObservableObject {
    // time, frequency, color (amplitude)
    typealias DSType = [Float]
    var graphType: GraphType = .spectrogram
    var rawData: [Any]? = [] // 
    var dsData: DSType? = [] // downsampled data

    var AVFile: AVAudioFile?
    var sampleRate: Double? // initialized by configure()
    var frequencyScale: FrequencyScale = .mel
    var config = SpectrogramConfig()
    var outputBins: Int { config.outputBins }
    var rollingWidth: Int { config.rollingWidth }
    var warp: FrequencyWarp

    var axisMinFrequency: Float { config.minFrequency }
    var axisMaxFrequency: Float { Float((sampleRate ?? 44100) / 2) }
    // axis forwarders: computed from main-owned state (scale / config / sampleRate), never the
    // queue-owned warp, so main-thread drawing can't race the queue's warp rebuild
    var frequencyTicks: [Float] {
        FrequencyWarp.frequencyTicks(scale: frequencyScale, maxFrequency: axisMaxFrequency, minFrequency: config.minFrequency)
    }
    func targetNormalPosition(frequency: Float) -> Float {
        FrequencyWarp.targetNormalizedPosition(scale: frequencyScale, frequency: frequency, minFrequency: config.minFrequency, maxFrequency: axisMaxFrequency)
    }
    
    // seconds of audio each column represents (hop / sampleRate). set by the producer
    // (StreamingManager for live, processFile for files); used to label the time axis.
    var secondsPerColumn: Double = 512.0 / 44100.0

    // emits timed intervals for profiling
    private let signposter = OSSignposter(subsystem: "AudioDemo", category: "render")
    
    // freq and amp. [amp1, amp2, amp3, ...], timeSlice[freqBin], spectrogramData[timeSlice][freqBin] = amp
    var spectrogramData: [[Float]] = [] // 2D array for time-frequency spectrogram of size rollingWidth x outputBins
    var warpedData: [[Float]] = [] // spectrogramData but fitted to mel rows (outputBins)
    var intensityData: [[Float]] = [] // cache for how bright it is, leave to colorMapping to determine color
    
    var floorDB: Float { get { config.floorDB } set { config.floorDB = newValue } }
    var ceilingDB: Float { get { config.ceilingDB } set { config.ceilingDB = newValue } }
    
    lazy var hannWindow = vDSP.window(ofType: Float.self,
                                 usingSequence: .hanningDenormalized,
                                 count: config.frameSize,
                                 isHalfWindow: false)
    // undo the inflation/deflation done by both the hann window, along with the general summing of all samples in a frame
    lazy var magnitudeScale: Float = 2 / vDSP.sum(hannWindow)
    lazy var dft: vDSP.DiscreteFourierTransform<Float> = {
        do {
            return try vDSP.DiscreteFourierTransform(previous: nil,
                                                     count: config.frameSize,
                                                     direction: .forward,
                                                     transformType: .complexComplex,
                                                     ofType: Float.self)
        } catch {
            fatalError("GraphManagerError.GenericFailure(funcName: \"init\", reason: \"failure to properly allocate DFT\"): \(error)")
        }
    }()
    
    init(config: SpectrogramConfig = SpectrogramConfig()) {
        self.config = config
        let defaultScale = FrequencyScale.mel
        self.frequencyScale = defaultScale
        self.warp = FrequencyWarp(scale: defaultScale, sampleRate: 44100, outputBins: config.outputBins, frameSize: config.frameSize, minFrequency: config.minFrequency, maxFrequency: 44100 / 2)
    }
    // need to convert spectrogramData elements into spectrogram cell
    // create DFT per-frame inside frameDFT to avoid referencing undefined symbols and to keep type-checking simple
    

    /*
     createIntensityColumn: create a frame of brightness values to be color mapped and stored in shared cache
     @: called by processAudio() and consume(); calls nothing
     needs: array of float values that contain magnitudes with range [0, infinity) but really [1e-9, 1.0]
     gives: array of float values that contain intensity brightness values with range [0, 1]
     ranges: floor/ceiling = dB window edges (default to floorDB/ceilingDB); for peak-relative pass ceiling = measured peak, floor = peak − span
     */
    func createIntensityColumn(from column: [Float], floor: Float? = nil, ceiling: Float? = nil) -> [Float] {
        // removed float divide and instead use multiply for like 10x performance increase (in optimal setting)
        // window edges: use the per-call values if given, else the instance defaults
        let lo = floor ?? floorDB
        let hi = ceiling ?? ceilingDB
        // guard a zero/negative span (would divide by zero) by flooring it at 1 dB
        let inverseSpan = 1 / max(hi - lo, 1e-6)
        var output = [Float](repeating: 0, count: column.count)
        // we pull the inner array out as a unsafemutablebufferpointer to avoid the atomic refcount update (expensive due to ordering constraints), now its simply non-atomic load and store operations (cheap!)
        column.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                for i in 0..<src.count {
                    // where src[i] is the magnitude value and src is the magnitudes of each frequency bin
                    let db = 20 * log10(max(src[i], 1e-9))
                    // v = clamp((d - lo) / (hi - lo), 0, 1) : default lo=-80, hi=0 -> (-35+80)/80 = 0.56
                    dst[i] = max(0, min(1, (db - lo) * inverseSpan))
                }
            }
        }
        return output
    }
    
    /*
     createSpectrumColumn: the most recent columns intensities
     @: called by the Canvas; calls nothing
     needs: intensityData or else it returns an empty array
     gives: a 0...1 intensity curve (one value per frequency bin), empty if no data yet
     */
    @MainActor func createSpectrumColumn() -> [Float] {
        intensityData.last ?? []
    }

    /*
     createLTASColumn: long-time average spectrum. averages the linear magnitudes of warpedData
     across all time columns, then maps to dB intensity
     @: called by the Canvas; calls createIntensityColumn()
     gives: a 0...1 intensity curve (one value per frequency bin), empty if no data yet
     */
    @MainActor func createLTASColumn() -> [Float] {
        guard let first = warpedData.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for col in warpedData {
            for i in 0..<min(col.count, sum.count) { sum[i] += col[i] }
        }
        let n = Float(warpedData.count)
        for i in 0..<sum.count { sum[i] /= n }
        return createIntensityColumn(from: sum)   // linear mean → dB → 0...1
    }

    // seconds of history currently held (columns × secondsPerColumn): the span of the
    // spectrogram's time axis.
    // ranges: returns seconds ≥ 0 (0 when no columns, up to rollingWidth × secondsPerColumn)
    var historySeconds: Double { Double(warpedData.count) * secondsPerColumn }

    // a "nice" time-tick step that yields roughly five labels across the given span.
    // ranges: span = seconds ≥ 0; returns one of {0.5, 1, 2, 5, 10, 20, 30, 60} seconds
    func timeTickStep(forSpan span: Double) -> Double {
        guard span > 0 else { return 1 }
        let raw = span / 5
        return [0.5, 1, 2, 5, 10, 20, 30, 60].first { $0 >= raw } ?? 60
    }

    /*
    createMagnitudeColumn: creates a live frame that is sourced from frameDFT and transformed into warped column via created frequency map and slice warping, heavy and runs on background queue
     @: called by processAudio() and consume(); calls frameDFT(timeFrame), sliceWrap(frameDFT output)
     needs: timeFrame, sampleRate and frequencyMap initialization via configure()
     gives: warped magnitudes in [0, ∞) (~1.0 for a full-scale sine), length outputBins (256)
     ranges: frame = time-domain samples ~[-1.0, 1.0], length MUST be 2048 (the DFT size);~
     */
    func createMagnitudeColumn(from frame: [Float]) throws -> [Float] {
        let liveFrame = try frameDFT(timeFrame: frame)
        return warp.sliceWarp(magnitudes: liveFrame)
    }
    
    /* appendColumn: cheap and lightweight, appends column of magnitudes to warpedData and column of intensity to intensityData, read by drawGraph on main thread. if the current image is full (> rollingWidth), drop the first X elements from warpedData and intensityData to fit in
     @: called by consume(); calls nothing
    needs: a float column of both intensities/magnitudes
    gives: an updated warpedData and intensityData at the correct size, along with an update-UI reminder
    ranges: magnitude = warped magnitudes [0, ∞); intensity = [0, 1]; both length outputBins (256). warpedData/intensityData capped at rollingWidth (512) columns
     */
    @MainActor func appendColumn(magnitude: [Float], intensity: [Float]) {
        warpedData.append(magnitude)
        intensityData.append(intensity)
        if warpedData.count > rollingWidth {
            let dropIndex = warpedData.count - rollingWidth
            warpedData.removeFirst(dropIndex)
            intensityData.removeFirst(dropIndex)
        }
        // re-renders any view watching this ObservableObject, since it isn't a @Published so wont update automactically
        objectWillChange.send()
    }
    
    // returns RGB values for blue > red > green for a given intensity value
    // buffers are lower level vs arrays and is a contiguoous block of memory, can be managed manually via pointers and UnsafeBufferPointer. convert array into buffer via array.withUnsafeBufferMutableBufferPointer. useful in audio cause easier and faster to access for realtime processing
    
    // frameLength = number of audio frames stored in the buffer (data quantity)
    // frameSize = number of samples chosen per frame (usually fixed value, analysis choice)
    // audioframe = one sample per channel at a given point in time (so could have N values with N channels)
    // if buffer.frameLength < frameSize, dont have enough samples and must accumulate across multiple buffers until frameSize is reached. frameSize samples is what we use to actually do the FFT
    
    /*
     processFile: the other option to live microphone input, works on already made files. clears spectrogramData completely, then checks if an avfile exists and that the buffer created from the avfile is not empty or nil. initializes rawData using the floatChannelData in whatever form its in, along with AVFile from the parameter, sample rate from the buffer, and creates the frequency map. then we proceed to downmix all of the channels into a one channel format stored in dsData and calls fileDFT() on it, then runs sliceWarp() and createIntensityColumn() on the result and stores both in warpedData and intensityData accordingly
     @: called by changeGraph(); calls frequencyMapping(), fileDFT(), sliceWarp(), and createIntensityColumn
     needs: valid AVAudioFile
     gives: frequencyMap, rawData, AVFile, and sampleRate initialization, and populates warpedData, dsData, and intensityData
     ranges: AVFile = any valid audio file (sampleRate typically 44100/48000 Hz); dsData = mono samples ~[-1.0, 1.0]; one column added per hop, intensity values in [0, 1]
     */
    func processFile(AVFile: AVAudioFile) throws {
        // reset accumulators so repeated calls cant stack duplicate frames
        spectrogramData.removeAll(keepingCapacity: true)
        // implement spectrogram processing
        if AVFile == AVFile { // what is even the point of this...
            guard let buffer = try AVAudioPCMBuffer(file: AVAudioFile(forReading: AVFile.url)),
                    buffer.floatChannelData != nil,
                    buffer.frameLength > 0
            else {
                throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "failure to properly allocate PCM buffer")
            }
            // difference between floatchanneldata accessed from avfile vs pcm buffer? probabaly that the buffer is more of a sample from the file and doesnt contain all encoded information
            self.rawData = [AVFile.floatChannelData() as Any]
            self.AVFile = AVFile
            self.sampleRate = buffer.format.sampleRate
            self.warp = FrequencyWarp(scale: frequencyScale, sampleRate: buffer.format.sampleRate, outputBins: outputBins, frameSize: config.frameSize, minFrequency: config.minFrequency, maxFrequency: Float(buffer.format.sampleRate / 2))
            let channelCount = Int(buffer.format.channelCount)
            // downmix all channels to a single mono channel format
            var downmix = [Float](repeating: 0, count: Int(buffer.frameLength))
            for channel in 0..<channelCount {
                let channelData = Array(UnsafeBufferPointer(
                    start: buffer.floatChannelData?[channel],
                    count: Int(buffer.frameLength)))
                for i in 0..<Int(buffer.frameLength) {
                    downmix[i] += channelData[i] / Float(channelCount)
                }
            }

            // an array of floats representing the mono waveform
            self.dsData = downmix
            let analysisHop = config.hopSize
            let frameCount = downmix.count >= config.frameSize
                ? (downmix.count - config.frameSize) / analysisHop + 1
                : 1
            let pool = max(1, Int((Double(frameCount) / Double(config.fileTargetColumns)).rounded(.up)))
            self.secondsPerColumn = Double(pool * analysisHop) / buffer.format.sampleRate
            try fileDFT(frameSize: config.frameSize, hopSize: analysisHop, pool: pool)
            // warp AFTER fileDFT has populated spectrogramData
            self.warpedData = spectrogramData.map { warp.sliceWarp(magnitudes: $0) }
            self.intensityData = warpedData.map { createIntensityColumn(from: $0)}
            
                    
        } else {
            throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "AVFile passed to processAudio does not match the AVFile stored in the WaveformGraph instance")
        }
    }

    /* fileDFT: takes dsData as input and outputs frequency-domain converted dsData, calls on bufferDFT multiple times. need to append results of bufferDFT() to the frequency-domain value address. if have left over values that dont fit into a frame, will create a new one padded with zeroes
     @: called by processAudio(); calls frameDFT()
     needs: frameSize and hopSize values, and a valid dsData
     gives: spectrogramData initialization
     ranges: frameSize = 2048 (must match the DFT size); hopSize ≥ 1 sample; each appended frame holds frameSize/2+1 = 1025 magnitudes in [0, ∞)
     */
    func fileDFT(frameSize: Int, hopSize: Int, pool: Int) throws {
        guard let dsData = self.dsData
        else {
            throw GraphManagerError.GenericFailure(funcName: "fileDFT", reason: "dsData does not exist")
        }
        let bins = frameSize / 2 + 1
        var column = [Float](repeating: 0, count: bins)
        var pooled = 0
        
        func flush() {
            guard pooled > 0 else { return }
            spectrogramData.append(column)
            column = [Float](repeating: 0, count: bins)
            pooled = 0
        }
        
        var bufferIndex = 0
        while bufferIndex + frameSize <= dsData.count {
            let timeFrame: [Float] = Array(dsData[bufferIndex..<(bufferIndex + frameSize)])
            guard let freqFrame = try? frameDFT(timeFrame: timeFrame)
            else {
                throw GraphManagerError.GenericFailure(funcName: "fileDFT", reason: "failed to create frequency frame")
            }
            for i in 0..<bins { column[i] = max(column[i], freqFrame[i]) }
            pooled += 1
            if pooled == pool { flush() }
            bufferIndex += hopSize
        }
        if bufferIndex < dsData.count {
            var timeFrame: [Float] = Array(dsData[bufferIndex..<dsData.count])
            timeFrame.append(contentsOf: Array(repeating: 0, count: frameSize - timeFrame.count))
            if let freqFrame = try? frameDFT(timeFrame: timeFrame) {
                for i in 0..<bins { column[i] = max(column[i], freqFrame[i]) }
                pooled += 1
            }
        }
        flush()
    }
    
    /*
     frameDFT: takes a buffer of discrete values, multiplies by the hann window, and does DFT on it to convert to frequency domain. upper half of the real values minus 1 are removed due to conjugate symmetry
     @: called by fileDFT() and createMagnitudeColumn, calls nothing
     needs: an array of amplitudes at time slice n, created from either fileDFT or createMagnitudeColumn
     gives: an array of magnitudes at frequency bin m
     ranges: timeFrame = time samples ~[-1.0, 1.0], length MUST be 2048; returns frameSize/2+1 = 1025 magnitudes in [0, ∞) (~1.0 for a full-scale sine)
     */
    func frameDFT(timeFrame: [Float]) throws -> [Float] {
        // apply Hann window
        let windowedData = vDSP.multiply(timeFrame, hannWindow)
        // prepare imaginary input
        let imaginary = [Float](repeating: 0, count: timeFrame.count)
        // create DFT for this frame size (explicit to help compiler)
        // perform transform and break into explicit sub-expressions
        let transformed = dft.transform(real: windowedData, imaginary: imaginary)
        let realPart = transformed.0
        let imagPart = transformed.1
        let uniqueCount = timeFrame.count / 2 + 1
        
        // wtf am i doing with my life ******************************************
        var magnitudes = [Float]()
        magnitudes.reserveCapacity((realPart.count / 2) + 1)
        // conjugate-symmetric dft output real-valued inputs :shrug:
        for i in 0..<((realPart.count / 2) + 1) {
            let r = realPart[i]
            let im = imagPart[i]
            magnitudes.append(sqrt(r * r + im * im) * magnitudeScale)
        }
        return Array(magnitudes[0..<uniqueCount])
    }
    // an array of arrays, where the outer dimension are time slices and each inner array is divided into freq bins, and the value in each bin represents the magnitude
    
    /*
     rebuildFrequencyWarp: rebuilds only the frequency map for when we change the frequency scaling, is deliberately not @MainActor. defaults to 44100 if sampleRate is not initialized
     @: called by setFrequencyScale; calls frequencyMapping
     needs: a given FrequencyScale type
     gives: an updated FrequencyScale type for the class instance
     ranges: scale = any FrequencyScale case; rebuilds frequencyMap over [40, Nyquist] 
     */
    func rebuildFrequencyWarp(scale: FrequencyScale) {
        let sr = sampleRate ?? 44100
        self.frequencyScale = scale
        self.warp = FrequencyWarp(scale: scale, sampleRate: sr, outputBins: config.frameSize,
                                  frameSize: outputBins, minFrequency: config.minFrequency,
                                             maxFrequency: Float(sr) / 2)
    }

    /*
     clearSpectrogramCaches(): clears warpedData and intensityData cache, useful as helper function
     @: called by setFrequencyScale; calls nothing
     needs: nothing
     gives: updated warpedData and intensityData
     */
    @MainActor func clearSpectrogramCaches() {
        warpedData.removeAll(keepingCapacity: true)
        intensityData.removeAll(keepingCapacity: true)
    }

    /*
     drawGraph: ...they do lots of things. checks if warpedData is empty, declares a cg image format and then flattens warpedData. converts flatSpectrogramData from an array to an unsafeMutableBufferPointer (has count, type, memory address, and built in bounds checking and iterates through intensityData, calculating its corresponding flat index to assign it to flatSpectrogramData. creates a pixelbuffer representing an image for each RGB channel, and then creating the final buffer when interleaved. expose flatSpectrogramDatas raw buffer as an unsafeBufferPointer and creates imageBuffer from it. it then applies the LUT to it, then creates a CG image from the rgb buffer
     @: called by ContentView; calls nothing
     needs: canvas size, populated warpedData, populated intensityData
     gives: cgImage
     ranges: reads intensityData in [0, 1]; returns a timeSlices × outputBins CGImage
     */
    @MainActor func drawGraph(rect: CGRect, color: Color, lineWidth: CGFloat) throws -> CGImage {
        // no columns yet, nothing to draw
        guard !warpedData.isEmpty else {
            throw GraphManagerError.GenericFailure(funcName: "drawGraph", reason: "no spectrogram data yet")
        }
        // time this call, shows up as an interval in instruments os_signpost row
        let interval = signposter.beginInterval("drawGraph", "columnCount = \(self.warpedData.count), rowCount = \(self.warpedData[0].count)")
        defer { signposter.endInterval("drawGraph", interval) }
        // created once actually called, implies spectrogram data exists at this point due to control flow
        lazy var timeSlices = warpedData.count
        lazy var freqBins = warpedData[0].count

        let rgbImageFormat = vImage_CGImageFormat(
            bitsPerComponent: 32,
            bitsPerPixel: 32 * 3,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: kCGBitmapByteOrder32Host.rawValue |
                CGBitmapInfo.floatComponents.rawValue |
                CGImageAlphaInfo.none.rawValue))!
        
        // convert spectrogramData from an array of [Float] to a contiguous block of memory
        var flatSpectrogramData = [Float](repeating: 0, count: timeSlices * freqBins)
        // the color LUT expects input in 0...1, but raw magnitudes span 0...130, so normalize...
        // removed float divide and instead use multiply for like 10x performance increase (in optimal setting)
        // we pull the inner array out as a unsafemutablebufferpointer to avoid the atomic refcount update (expensive due to ordering constraints), now its simply non-atomic load and store operations (cheap!)
        flatSpectrogramData.withUnsafeMutableBufferPointer { dst in
            for timeSlice in 0..<timeSlices {
                intensityData[timeSlice].withUnsafeBufferPointer { col in
                    for freqBin in 0..<freqBins {
                        let flatIndex = (freqBins - 1 - freqBin) * timeSlices + timeSlice
                        dst[flatIndex] = col[freqBin]
                    }
                }
            }
        }
        let redBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: timeSlices, height: freqBins)
        let greenBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: timeSlices, height: freqBins)
        let blueBuffer = vImage.PixelBuffer<vImage.PlanarF>(width: timeSlices, height: freqBins)
        let rgbBuffer = vImage.PixelBuffer<vImage.InterleavedFx3>(width: timeSlices, height: freqBins)
        
        // discards result and asserts this returns nothing "void-type"
        let _: () = flatSpectrogramData.withUnsafeMutableBufferPointer { pixels in
            let imageBuffer = vImage.PixelBuffer(
                data: pixels.baseAddress!,
                width: timeSlices,
                height: freqBins,
                byteCountPerRow: timeSlices * MemoryLayout<Float>.stride,
                pixelFormat: vImage.PlanarF.self)
            
            SpectrogramGraph.multidimensionalLookupTable.apply(
                sources: [imageBuffer],
                destinations: [redBuffer, greenBuffer, blueBuffer],
                interpolation: .half)

            rgbBuffer.interleave(planarSourceBuffers: [redBuffer, greenBuffer, blueBuffer])
        }
        guard let cgImage = rgbBuffer.makeCGImage(cgImageFormat: rgbImageFormat) else {
            throw GraphManagerError.GenericFailure(funcName: "drawGraph2", reason: "failed to create CGImage from rgbBuffer")
        }
        return cgImage // ?? SpectrogramGraph.emptyCGImage
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

extension SpectrogramGraph: StreamingConsumer {
    /*
     configure: initializes sampleRate and frequencyMap based off of given sampleRate
     @: called by start(); calls frequencyMapping()
     needs: sampleRate
     gives: frequencyMap and sampleRate initialization
     ranges: sampleRate > 0 Hz (typically 44100/48000); builds frequencyMap over [40, Nyquist] with frameSize 2048, outputRows = outputBins (256)
     */
    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.warp = FrequencyWarp(scale: frequencyScale, sampleRate: sampleRate, outputBins: config.outputBins, frameSize: config.frameSize, minFrequency: config.minFrequency, maxFrequency: Float(sampleRate) / 2) }
    /*
     consume: guards creation of magnitude column, then creates intensity column from the magnitude column and appends both to the graph via MainActor task
     @: called by packager(); calls createMagnitudeColumn(), createIntensityColumn(), and appendColumn()
     needs: float array of amplitudes
     gives: graph update via CG image
     ranges: frame = time samples [-1.0, 1.0], length must be 2048; appends one magnitude column [0, ∞) and one intensity column [0, 1]
     */
    func consume(frame: [Float]) {
        guard let magnitude = try? createMagnitudeColumn(from: frame)
        else { return }
        let intensity = createIntensityColumn(from: magnitude)
        Task { @MainActor in self.appendColumn(magnitude: magnitude, intensity: intensity) }
    }
}
