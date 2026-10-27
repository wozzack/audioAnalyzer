import AVFoundation
import AudioKit
import SwiftUI
import Waveform
import Accelerate
import os

struct FrequencyMap {
    let lo: [Int]
    let hi: [Int]
    let frac: [Float]
    let outputBins: Int
}

struct FrequencyWarp {
    
    let scale: FrequencyScale
    let map: FrequencyMap
    let freqSteps: [Float]
    let sampleRate: Double
    let minFrequency: Float
    let maxFrequency: Float
    let outputBins: Int
    let frameSize: Int
    
    init(scale: FrequencyScale, sampleRate: Double, outputBins: Int, frameSize: Int, minFrequency: Float, maxFrequency: Float) {
        self.scale = scale
        self.sampleRate = sampleRate
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.outputBins = outputBins
        self.frameSize = frameSize
        // builds frequency ticks
        self.freqSteps = FrequencyWarp.frequencyTicks(scale: scale, maxFrequency: maxFrequency, minFrequency: minFrequency)
        /*
         frequency mapping algorithm: creates a range of frequencies for each bin in outputRows. starts with three arrays initialized with zeroes, and then computes the target frequency for each bin, and then stores the three arrays within a FrequencyMap structure.
         @: called by configure() and processAudio(); calls targetFrequency()
         needs: frequency scaling type, samplerate, framesize, output rows, min/max frequency
         gives: FrequencyMap object for the given configuration
         ranges: sampleRate > 0 Hz; frameSize = 2048; outputRows ≥ 1 (=outputBins); 0 < minFrequency < maxFrequency ≤ Nyquist (Hz). returns lo/hi bin indices in [0, frameSize/2] (0...1024) and frac weights in [0, 1]
         */
        let numBins = (frameSize / 2) + 1 // conjugate symmetry only half are unique values
        var lo = [Int](repeating: 0, count: outputBins)
        var hi = [Int](repeating: 0, count: outputBins)
        var frac = [Float](repeating: 0, count: outputBins)
        for i in 0..<outputBins {
            let freq = FrequencyWarp.targetFrequency(row: i, totalRows: outputBins, scale: scale, maxFrequency: maxFrequency, minFrequency: minFrequency)
            let x = min(max(freq * Float(frameSize) / Float(sampleRate), 0), Float(numBins - 1))
            let l = Int(x.rounded(.down))
            lo[i] = l
            hi[i] = min(Int(l) + 1, numBins - 1)
            frac[i] = x - Float(l)
        }
        self.map = FrequencyMap(lo: lo, hi: hi, frac: frac, outputBins: outputBins)
        
    }
    
    /*
     hzToMel and melToHz: o'shaughnessy 1987, converts between hertz and mel
     @: called by targetFrequency; calls nothing
     needs: float value parameter
     gives: converted float value
     ranges: hzToMel: f = Hz ≥ 0 → mels ≥ 0; melToHz: m = mels ≥ 0 → Hz ≥ 0 (monotonic both ways)
     */
    static func hzToMel(f: Float) -> Float {
        2595 * log10(1 + f / 700)
    }
    
    static func melToHz(_ m: Float) -> Float {
        700 * (pow(10, m / 2595) - 1)
    }
    
    /*
     targetFrequency: decides frequency depending on enum FrequencyScale, output is the frequency that the input row represents
     @: called by frequencyMapping(); calls hzToMel() and melToHz()
     needs: current row, total rows, frequency scale type, max frequency, and mininum frequency
     gives: frequency to compute range of bins in frequencyMap type
     ranges: row = [0, totalRows-1]; totalRows ≥ 2; 0 < minFrequency < maxFrequency ≤ Nyquist (Hz); returns Hz in [minFrequency, maxFrequency]
     */
    static func targetFrequency(row: Int, totalRows: Int, scale: FrequencyScale, maxFrequency: Float, minFrequency: Float) -> Float {
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
    targetNormalizedPosition: inverse of targetFrequency: decides normalized position, output is the mormalized value that determines ... lets curve axis labels line up with the warped x-axis
     @: called by drawCurve() and drawSpectrogramAxes(); calls hzToMel()
     needs: input frequency to be mapped, frequencyScale type
     gives: normalized position value from [0, 1]
     ranges: f = any Hz (clamped internally to [40, Nyquist])
     */
    static func targetNormalizedPosition(scale: FrequencyScale, frequency: Float, minFrequency: Float, maxFrequency: Float) -> Float {
        let lo = minFrequency
        let hi = maxFrequency
        let x = min(max(frequency, lo), hi)
        switch scale {
        case .linear:
            return (x - lo) / (hi - lo)
        case .log:
            return log(x / lo) / log(hi / lo)
        case .mel:
            return (FrequencyWarp.hzToMel(f: x) - FrequencyWarp.hzToMel(f: lo)) / (FrequencyWarp.hzToMel(f: hi) - FrequencyWarp.hzToMel(f: lo))
        }
    }
    
    // the frequency range the axis spans (matches what frequencyMapping uses)
    // ranges: both in Hz. min = 40; max = Nyquist = sampleRate/2 (≈22050 at 44.1 kHz, ≈24000 at 48 kHz)
    static func frequencyTicks(scale: FrequencyScale, maxFrequency: Float, minFrequency: Float) -> [Float] {
        let candidates: [Float] = (scale == .linear)
        ? Array(stride(from: 0, through: maxFrequency, by: 2000))
            : [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
        // walks through array and accepts values that meet both conditions
        return candidates.filter { $0 >= minFrequency && $0 <= maxFrequency }
    }
    
    /*
     sliceWarp: converts a range of frequency bins into another range of bins, mapping determined by the FrequencyMap. for each iterative index of the output, compute the value via map decoding
     @: called by processAudio() and createMagnitudeColumn(); calls nothing
     needs: float array of magnitudes and a frequency map
     gives: warped float array of magnitudes
     ranges: magnitudes = [0, ∞), length frameSize/2+1 = 1025; returns [0, ∞), length map.outputBins (256). interpolation preserves the input's range
     */
    func sliceWarp(magnitudes: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: self.map.outputBins)
        for i in 0..<self.map.outputBins {
            let a = magnitudes[self.map.lo[i]]
            let b = magnitudes[self.map.hi[i]]
            output[i] = a * (1 - self.map.frac[i]) + b * self.map.frac[i]
        }
        return output
    }
    
    
}
