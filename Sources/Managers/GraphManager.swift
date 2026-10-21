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
    var frequencyMap: FrequencyMap? // initialized by configure()
    var config = SpectrogramConfig()
    var outputBins: Int { config.outputBins }
    var rollingWidth: Int { config.rollingWidth }
    
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

    // need to convert spectrogramData elements into spectrogram cell
    // create DFT per-frame inside frameDFT to avoid referencing undefined symbols and to keep type-checking simple
    
    struct FrequencyMap {
        let lo: [Int]
        let hi: [Int]
        let frac: [Float]
        let outputBins: Int
    }
    
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
    
    func peakdB(cells: [[Float]]) -> Float {
        
        return 0.0
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

    // the frequency range the axis spans (matches what frequencyMapping uses)
    // ranges: both in Hz. min = 40; max = Nyquist = sampleRate/2 (≈22050 at 44.1 kHz, ≈24000 at 48 kHz)
    var axisMinFrequency: Float { config.minFrequency }
    var axisMaxFrequency: Float { Float((sampleRate ?? 44100) / 2) }

    // inverse of targetFrequency: where (0...1, left→right) a given frequency sits on
    // the current scale. lets curve axis labels line up with the warped x-axis.
    // ranges: f = any Hz (clamped internally to [40, Nyquist]); returns a position in [0, 1]
    func normalizedPosition(forFrequency f: Float) -> Float {
        let lo = axisMinFrequency, hi = axisMaxFrequency
        let x = min(max(f, lo), hi)
        switch frequencyScale {
        case .linear: return (x - lo) / (hi - lo)
        case .log:    return log(x / lo) / log(hi / lo)
        case .mel:    return (hzToMel(f: x) - hzToMel(f: lo)) / (hzToMel(f: hi) - hzToMel(f: lo))
        }
    }

    // which frequencies get a gridline/label on the current scale, clipped to the visible
    // axis range. a data decision (not a drawing one), shared by every view that renders a
    // frequency axis so the spectrogram and the curves stay in sync.
    // ranges: returns Hz values, each within [40, Nyquist] (subset of a fixed candidate set)
    var frequencyTicks: [Float] {
        let candidates: [Float] = (frequencyScale == .linear)
            ? Array(stride(from: 0, through: axisMaxFrequency, by: 2000))
            : [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
        return candidates.filter { $0 >= axisMinFrequency && $0 <= axisMaxFrequency }
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
        guard let map = frequencyMap
        else {
            throw GraphManagerError.GenericFailure(funcName: "createColumn", reason: "failed frequency map guard.")
        }
        return sliceWarp(magnitudes: liveFrame, map: map)
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
            self.frequencyMap = frequencyMapping(scale: frequencyScale, sampleRate: buffer.format.sampleRate, frameSize: config.frameSize, outputRows: outputBins, minFrequency: config.minFrequency, maxFrequency: Float(buffer.format.sampleRate / 2))
            guard let frequencyMap = self.frequencyMap
            else {
                throw GraphManagerError.GenericFailure(funcName: "processAudio", reason: "Frequency map failed to build.")}
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
            self.warpedData = spectrogramData.map { sliceWarp(magnitudes: $0, map: frequencyMap) }
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
     hzToMel and melToHz: o'shaughnessy 1987, converts between hertz and mel
     @: called by targetFrequency; calls nothing
     needs: float value parameter
     gives: converted float value
     ranges: hzToMel: f = Hz ≥ 0 → mels ≥ 0; melToHz: m = mels ≥ 0 → Hz ≥ 0 (monotonic both ways)
     */
    func hzToMel(f: Float) -> Float {
        2595 * log10(1 + f / 700)
    }
    
    func melToHz(_ m: Float) -> Float {
        700 * (pow(10, m / 2595) - 1)
    }
    
    /*
     targetFrequency: creates frequency bins depending on enum FrequencyScale, output is the frequency that the input row represents
     @: called by frequencyMapping(); calls hzToMel() and melToHz()
     needs: current row, total rows, frequency scale type, max frequency, and mininum frequency
     gives: frequency to compute range of bins in frequencyMap type
     ranges: row = [0, totalRows-1]; totalRows ≥ 2; 0 < minFrequency < maxFrequency ≤ Nyquist (Hz); returns Hz in [minFrequency, maxFrequency]
     */
    func targetFrequency(row: Int, totalRows: Int, scale: FrequencyScale, maxFrequency: Float, minFrequency: Float) -> Float {
        let normalizedPosition = Float(row) / Float(totalRows - 1) // scale of 0.0 to 1.0
        switch scale {
        case .linear:
            return minFrequency + (maxFrequency - minFrequency) * normalizedPosition
        case .log:
            return minFrequency * pow(maxFrequency / minFrequency, normalizedPosition)
        case .mel:
            let m = hzToMel(f: minFrequency) + (hzToMel(f: maxFrequency) - hzToMel(f: minFrequency)) * normalizedPosition
            return melToHz(m)
        }
    }
    
    /*
     rebuildFrequencyMap: rebuilds only the frequency map for when we change the frequency scaling, is deliberately not @MainActor. defaults to 4410 if sampleRate is not initialized
     @: called by setFrequencyScale; calls frequencyMapping
     needs: a given FrequencyScale type
     gives: an updated FrequencyScale type for the class instance
     ranges: scale = any FrequencyScale case; rebuilds frequencyMap over [40, Nyquist] (sampleRate defaults to 44100 Hz if unset)
     */
    func rebuildFrequencyMap(scale: FrequencyScale) {
        let sr = sampleRate ?? 44100
        self.frequencyScale = scale
        self.frequencyMap = frequencyMapping(scale: scale, sampleRate: sr, frameSize: config.frameSize,
                                             outputRows: outputBins, minFrequency: config.minFrequency,
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
     frequencyMapping: creates a range of frequencies for each bin in outputRows. starts with three arrays initialized with zeroes, and then computes the target frequency for each bin, and then stores the three arrays within a FrequencyMap structure.
     @: called by configure() and processAudio(); calls targetFrequency()
     needs: frequency scaling type, samplerate, framesize, output rows, min/max frequency
     gives: FrequencyMap object for the given configuration
     ranges: sampleRate > 0 Hz; frameSize = 2048; outputRows ≥ 1 (=outputBins); 0 < minFrequency < maxFrequency ≤ Nyquist (Hz). returns lo/hi bin indices in [0, frameSize/2] (0...1024) and frac weights in [0, 1]
     */
    func frequencyMapping(scale: FrequencyScale, sampleRate: Double, frameSize: Int, outputRows: Int, minFrequency: Float, maxFrequency: Float) -> FrequencyMap {
        let numBins = (frameSize / 2) + 1 // conjugate-symmetry, only half are unique values
        var lo = [Int](repeating: 0, count: outputRows)
        var hi = [Int](repeating: 0, count: outputRows)
        var frac = [Float](repeating: 0, count: outputRows)
        for i in 0..<outputRows {
            let freq = targetFrequency(row: i, totalRows: outputRows, scale: scale, maxFrequency: maxFrequency, minFrequency: minFrequency)
            let x = min(max(freq * Float(frameSize) / Float(sampleRate), 0), Float(numBins - 1))
            let l = Int(x.rounded(.down))
            lo[i] = l
            hi[i] = min(Int(l) + 1, numBins - 1)
            frac[i] = x - Float(l)
        }
        return FrequencyMap(lo: lo, hi: hi, frac: frac, outputBins: outputRows)
    }
    
    /*
     sliceWarp: converts a range of frequency bins into another range of bins, mapping determined by the FrequencyMap. for each iterative index of the output, compute the value via map decoding
     @: called by processAudio() and createMagnitudeColumn(); calls nothing
     needs: float array of magnitudes and a frequency map
     gives: warped float array of magnitudes
     ranges: magnitudes = [0, ∞), length frameSize/2+1 = 1025; returns [0, ∞), length map.outputBins (256). interpolation preserves the input's range
     */
    func sliceWarp(magnitudes: [Float], map: FrequencyMap) -> [Float] {
        var output = [Float](repeating: 0, count: map.outputBins)
        for i in 0..<map.outputBins {
            let a = magnitudes[map.lo[i]]
            let b = magnitudes[map.hi[i]]
            output[i] = a * (1 - map.frac[i]) + b * map.frac[i]
        }
        return output
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
        self.frequencyMap = frequencyMapping(scale: frequencyScale, sampleRate: sampleRate, frameSize: config.frameSize, outputRows: outputBins, minFrequency: config.minFrequency, maxFrequency: Float(sampleRate) / 2) }
    /*
     consume: guards creation of magnitude column, then creates intensity column from the magnitude column and appends both to the graph via MainActor task
     @: called by packager(); calls createMagnitudeColumn(), createIntensityColumn(), and appendColumn()
     needs: float array of amplitudes
     gives: graph update via CG image
     ranges: frame = time samples ~[-1.0, 1.0], length MUST be 2048; appends one magnitude column [0, ∞) and one intensity column [0, 1]
     */
    func consume(frame: [Float]) {
        guard let magnitude = try? createMagnitudeColumn(from: frame)
        else { return }
        let intensity = createIntensityColumn(from: magnitude)
        Task { @MainActor in self.appendColumn(magnitude: magnitude, intensity: intensity) }
    }
}
