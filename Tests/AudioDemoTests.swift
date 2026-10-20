
import Testing
import SwiftUI
import AudioKit
import AVFoundation
import Foundation
import Atomics

@testable import AudioDemo

class AudioManagerTestSuite {
    init() {
        print("Starting AudioManager Test Suite.")
    }

    deinit {
        print("Ending AudioManager Test Suite.")
    }
    // need tests for seeking bar, playlist, loading audio, and convert helper functions
    // lossy formats: mp3, aac
    // lossless formats: flac, alac
    // uncompressed formats: wav, aiff
    @Test func stringsToPlaylist() throws {
        let audioManager = AudioManager()
        let validStrings = ["misato.mp3", "asuka.wav", "rei.flac", "kaji.m4a"]
        let invalidStrings = ["invalidfile.txt", ".wav", "audiofile.mp3.mp4", ""]
        for string in validStrings {
            do {
                try audioManager.addToPlaylist(audio: convertToAudioObject(s: string))
            } catch {
                throw AudioManagerError.GenericFailure(funcName: "addToPlaylist", reason: "Failed to add valid audio object to playlist for string \(string)")
            }
        }
        for string in invalidStrings {
            do {
                try audioManager.addToPlaylist(audio: convertToAudioObject(s: string))

            } catch {
                // expected error, do nothing
                #expect(validStrings.count == audioManager.playlist.count, "Playlist should only contain valid audio objects added from valid strings.")
            }
        }
        #expect(audioManager.playlist.count == validStrings.count, "Playlist should contain only valid audio objects added from valid strings.")
    }

    @Test func loadFromPlaylist() throws {
        let audioManager = AudioManager()
        let validStrings = ["misato.mp3", "asuka.wav", "rei.flac", "kaji.m4a"]
        for string in validStrings {
            do {
                try audioManager.addToPlaylist(audio: convertToAudioObject(s: string))
            } catch {
                throw AudioManagerError.GenericFailure(funcName: "addToPlaylist", reason: "Failed to add valid audio object to playlist for string \(string)")
            }
        }

        for audio in audioManager.playlist {
            do {
                try audioManager.loadAudio(audio: audio)
            } catch {
                throw AudioManagerError.GenericFailure(funcName: "loadAudio", reason: "Failed to load audio object from playlist for audio \(audio.name)")
            }
            #expect(audioManager.isLoaded == true, "AudioManager should have successfully loaded audio object \(audio.name) from playlist.")
        }
    }

    // should also test pause on stop for invaid
    @Test func playback() throws {
        let audioManager = AudioManager()
        try audioManager.addToPlaylist(audio: convertToAudioObject(s: "misato.mp3"))
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        do {
            try audioManager.playAudio()
            #expect(audioManager.player.status == .playing, "AudioManager player should be in started status after calling playAudio.")
            try audioManager.pauseAudio()
            #expect(audioManager.player.status == .paused, "AudioManager player should be in paused status after calling pauseAudio.")
            try audioManager.playAudio()
            #expect(audioManager.player.status == .playing, "AudioManager player should be in started status after calling playAudio again after stopping.")
            try audioManager.stopAudio()
            #expect(audioManager.player.status == .stopped, "AudioManager player should be in stopped status after calling stopAudio.")
        }

        do {
            try audioManager.pauseAudio()
        } catch let error {
            #expect(error is AudioManagerError)
        }
    }

    @Test func seeking() throws {
        let audioManager = AudioManager()
        try audioManager.addToPlaylist(audio: convertToAudioObject(s: "misato.mp3"))
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try audioManager.playAudio()
        try audioManager.manualSeeking(prog: 0.5)
        #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() / 2, "AudioManager player should be at halfway point of duration after seeking to 0.5 progress.")
        try audioManager.manualSeeking(prog: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() * 0.8, "AudioManager player should be at 80% point of duration after seeking to 0.8 progress.")
        }

        try audioManager.manualSeeking(prog: 0.25)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            #expect(audioManager.player.currentTime.rounded() == audioManager.player.duration.rounded() * 0.25, "AudioManager player should be at 25% point of duration after seeking to 0.25 progress.")
        }
    }

    // add, reject duplicates, remove, and clear the playlist.
    @Test func playlistMutation() throws {
        let audioManager = AudioManager()
        let audio = try convertToAudioObject(s: "misato.mp3")

        try audioManager.addToPlaylist(audio: audio)
        #expect(audioManager.playlist.count == 1)

        #expect(throws: AudioManagerError.self, "adding a duplicate should throw") {
            try audioManager.addToPlaylist(audio: audio)
        }
        #expect(audioManager.playlist.count == 1, "duplicate must not be added")

        try audioManager.removeFromPlaylist(audio: audio)
        #expect(audioManager.playlist.isEmpty, "remove should empty the playlist")

        #expect(throws: AudioManagerError.self, "removing a missing item should throw") {
            try audioManager.removeFromPlaylist(audio: audio)
        }

        try audioManager.addToPlaylist(audio: audio)
        audioManager.clearPlaylist()
        #expect(audioManager.playlist.isEmpty, "clearPlaylist should empty the playlist")
    }
}

class CanvasManagerTestSuite {
    init() {
        print("Starting CanvasManager Test Suite.")
    }

    deinit {
        print("Ending CanvasManager Test Suite.")
    }

    @Test func changeGraph() throws {
        let testFile = try convertToAudioObject(s: "misato.mp3")
        let testFile2 = try convertToAudioObject(s: "asuka.wav")
        let canvasManager = CanvasManager()
        do {
            try canvasManager.changeGraph(newGraph: .waveform, file: testFile.file)
            #expect(canvasManager.visualModel is WaveformGraph, "visualModel is of wrong type")
            #expect(canvasManager.visualModel!.dsData != nil, "dsData is nil")
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to change visualModel and it's properties correctly.")
        }

        do {
            try canvasManager.changeGraph(newGraph: .spectrogram, file: testFile2.file)
            #expect(canvasManager.visualModel is SpectrogramGraph, "visualModel is of wrong type")
            #expect(canvasManager.visualModel!.dsData != nil, "dsData is nil")
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to change visualModel and it's properties correctly.")
        }
    }

    @Test func isGraphShowing() {
        let canvasManager = CanvasManager()
        canvasManager.clearGraph()
        #expect(canvasManager.graphShowing == false)
    }

}

class GraphManagerTestSuite {
    init() {
        print("Starting GraphManager Test Suite.")
    }

    deinit {
        print("Ending GraphManager Test Suite.")
    }
    // test for success and failure scenarios, check relevant states for correct values, not just existance. test for single and multi channel audio files, pass invalid file and assert the correct error is thrown.
    @Test func waveformProcessing() throws {
        // prechecklist stuff type shit
        let audioManager = AudioManager()
        let canvasManager = CanvasManager()
        let testAudioObject = try convertToAudioObject(s: "misato.mp3")
        let testAudioObject2 = try convertToAudioObject(s: "asuka.wav")
        try audioManager.addToPlaylist(audio: testAudioObject)
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject.file)

        // success
        do {
            try canvasManager.visualModel?.processFile(AVFile: testAudioObject.file)
            // check that they are not nil
            #expect(canvasManager.visualModel?.rawData != nil)
            // dsData is type-erased through `any VisualGraph`, so cast to the concrete type
            let dsData = (canvasManager.visualModel as? WaveformGraph)?.dsData
            #expect(dsData != nil)
            #expect((dsData?.count ?? 0) > 0, "dsData should not be empty" )

            // check that dsData values are valid, normalized, and in logical ordering
            if let dsData {
                for (min, max) in dsData {
                    #expect(min <= max, "min values range exceeds that of max values range")
                    #expect(min >= -1.0 && max <= 1.0, "min and max values are not normalized between -1.0 and 1.0")
                }
            }
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "processFile", reason: "failed to process audio for testAudioObject1")
        }

        // failure due to mismatched files
        do {
            try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject2.file)
        } catch let error {
            #expect(error is GraphManagerError)
        }

        do {
            try canvasManager.visualModel?.processFile(AVFile: testAudioObject2.file)
            try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject2.file)
            // check that they are not nil
            #expect(canvasManager.visualModel?.rawData != nil)
            let dsData = (canvasManager.visualModel as? WaveformGraph)?.dsData
            #expect(dsData != nil)
            #expect((dsData?.count ?? 0) > 0, "dsData should not be empty" )

            // check that dsData values are valid, normalized, and in logical ordering
            if let dsData {
                for (min, max) in dsData {
                    #expect(min <= max, "min values range exceeds that of max values range")
                    #expect(min >= -1.0 && max <= 1.0, "min and max values are not normalized between -1.0 and 1.0")
                }
            }
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "processFile", reason: "failed to process audio for testAudioObject2")
        }
    }

    @MainActor @Test func waveformDrawing() throws {
        let audioManager = AudioManager()
        let canvasManager = CanvasManager()
        let testAudioObject = try convertToAudioObject(s: "misato.mp3")
        try audioManager.addToPlaylist(audio: testAudioObject)
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject.file)
        try canvasManager.visualModel?.processFile(AVFile: testAudioObject.file)
        let displaySize = CGRect(x: 0, y: 0, width: 300, height: 600)

        // what do i want to check for in the pathobject?

        let pathObject = try canvasManager.visualModel?.drawGraph(rect: displaySize, color: .blue, lineWidth: 1.0)

        #expect(pathObject != nil)

    }

    // qa 440 Hz sine, run through one column of the live spectrogram path
    // (frequencyMapping -> frameDFT -> sliceWarp), should peak on the mel row
    // that maps back to ~440 Hz. frameSize matches the fixed 2048-point DFT.
    @Test func liveColumnSineMapping() throws {
        let sampleRate = 44100.0
        let frameSize = 2048
        let testFreq = 440.0

        let sv = SpectrogramGraph()
        // match the internal array sizing (frequencyMapping sizes its arrays with outputBins)
        let outputRows = sv.outputBins

        // one frame of a pure 440 Hz sine
        let frame: [Float] = (0..<frameSize).map { i in
            Float(sin(2 * Double.pi * testFreq * Double(i) / sampleRate))
        }

        // build the mel map and produce one warped column
        let map = sv.frequencyMapping(scale: .mel, sampleRate: sampleRate, frameSize: frameSize,
                                      outputRows: outputRows, minFrequency: 40,
                                      maxFrequency: Float(sampleRate / 2))
        let linear = try sv.frameDFT(timeFrame: frame)          // 1025 linear magnitudes
        let column = sv.sliceWarp(magnitudes: linear, map: map) // outputRows warped values

        #expect(column.count == outputRows, "warped column should have one value per output row")

        // brightest row -> convert back to Hz and check it lands near 440
        guard let peakRow = column.indices.max(by: { column[$0] < column[$1] }) else {
            throw GraphManagerError.GenericFailure(funcName: "liveColumnSineMapping", reason: "empty warped column")
        }
        let peakFreq = sv.targetFrequency(row: peakRow, totalRows: outputRows, scale: .mel,
                                          maxFrequency: Float(sampleRate / 2), minFrequency: 40)

        // FFT bin resolution is 44100/2048 ≈ 21.5 Hz, so allow ~a couple bins of slack
        #expect(abs(peakFreq - Float(testFreq)) < 60,
                "expected peak near \(testFreq) Hz, got \(peakFreq) Hz at row \(peakRow)")
    }

    // a high-frequency tone must map to a high mel row. This fails if numBins is
    // derived from outputRows instead of frameSize (which clamps high bins onto one row).
    @Test func liveColumnHighFrequencyMapping() throws {
        let sampleRate = 44100.0
        let frameSize = 2048
        let testFreq = 15000.0

        let sv = SpectrogramGraph()
        let outputRows = sv.outputBins
        let frame: [Float] = (0..<frameSize).map { i in
            Float(sin(2 * Double.pi * testFreq * Double(i) / sampleRate))
        }
        let map = sv.frequencyMapping(scale: .mel, sampleRate: sampleRate, frameSize: frameSize,
                                      outputRows: outputRows, minFrequency: 40,
                                      maxFrequency: Float(sampleRate / 2))
        let linear = try sv.frameDFT(timeFrame: frame)
        let column = sv.sliceWarp(magnitudes: linear, map: map)

        guard let peakRow = column.indices.max(by: { column[$0] < column[$1] }) else {
            throw GraphManagerError.GenericFailure(funcName: "liveColumnHighFrequencyMapping", reason: "empty column")
        }
        let peakFreq = sv.targetFrequency(row: peakRow, totalRows: outputRows, scale: .mel,
                                          maxFrequency: Float(sampleRate / 2), minFrequency: 40)
        // mel rows are widely spaced up here (~80 Hz/row), so allow generous slack
        #expect(abs(peakFreq - Float(testFreq)) < 500,
                "expected peak near \(testFreq) Hz, got \(peakFreq) Hz at row \(peakRow)")
    }

    // configure() must build the frequency map before columns can be made.
    @Test func liveConfigureBuildsFrequencyMap() throws {
        let sv = SpectrogramGraph()
        #expect(sv.frequencyMap == nil, "no map before configure")
        sv.configure(sampleRate: 44100)
        #expect(sv.frequencyMap != nil, "configure should build the frequency map")

        // frameSize matches the fixed 2048-point DFT used by frameDFT
        let column = try sv.createMagnitudeColumn(from: [Float](repeating: 0, count: 2048))
        #expect(column.count == sv.outputBins, "column should have one value per output row")
    }

    // appendColumn scrolls: BOTH caches must stay capped at rollingWidth. (Regression
    // guard for the earlier bug where intensityData wasn't trimmed alongside warpedData.)
    @MainActor @Test func appendColumnRespectsRollingWidth() {
        let sv = SpectrogramGraph()
        let magnitude = [Float](repeating: 0.5, count: sv.outputBins)
        let intensity = sv.createIntensityColumn(from: magnitude)
        for _ in 0..<(sv.rollingWidth + 50) {
            sv.appendColumn(magnitude: magnitude, intensity: intensity)
        }
        #expect(sv.warpedData.count == sv.rollingWidth,
                "warpedData should cap at rollingWidth, got \(sv.warpedData.count)")
        #expect(sv.intensityData.count == sv.rollingWidth,
                "intensityData should cap at rollingWidth, got \(sv.intensityData.count)")
    }

    // the mel map should be well-formed: right length, monotonic bins, valid weights.
    @Test func frequencyMapIsWellFormed() {
        let sv = SpectrogramGraph()
        let map = sv.frequencyMapping(scale: .mel, sampleRate: 44100, frameSize: 2048,
                                      outputRows: sv.outputBins, minFrequency: 40,
                                      maxFrequency: 22050)
        #expect(map.lo.count == sv.outputBins)
        #expect(map.hi.count == sv.outputBins)
        #expect(map.frac.count == sv.outputBins)
        // mel frequency increases with row, so source bins must be non-decreasing
        var previous = -1
        for value in map.lo {
            #expect(value >= previous, "lo bins should be non-decreasing on a mel axis")
            previous = value
        }
        // interpolation weights are always in [0, 1]
        #expect(map.frac.allSatisfy { $0 >= 0 && $0 <= 1 }, "frac must be a 0...1 weight")
        // hi is never below lo
        #expect(zip(map.lo, map.hi).allSatisfy { $0 <= $1 }, "hi bin must be >= lo bin")
    }

    // axis range tracks the sample rate: min is fixed at 40 Hz, max is Nyquist.
    @Test func axisRangeMatchesSampleRate() {
        let sv = SpectrogramGraph()
        #expect(sv.axisMinFrequency == 40)
        #expect(sv.axisMaxFrequency == 22050, "defaults to 44100/2 before configure")
        sv.configure(sampleRate: 48000)
        #expect(sv.axisMaxFrequency == 24000, "max should follow the configured sample rate")
    }

    // normalizedPosition maps the axis endpoints to 0/1, clamps out-of-range input, and
    // rises monotonically with frequency on every scale. this is what lines axis labels
    // up with the warped image.
    @Test func normalizedPositionEndpointsAndMonotonic() {
        let sv = SpectrogramGraph()   // Nyquist 22050
        for scale in FrequencyScale.allCases {
            sv.frequencyScale = scale
            let lo = sv.normalizedPosition(forFrequency: sv.axisMinFrequency)
            let hi = sv.normalizedPosition(forFrequency: sv.axisMaxFrequency)
            #expect(abs(lo - 0) < 1e-4, "\(scale): min frequency maps to 0")
            #expect(abs(hi - 1) < 1e-4, "\(scale): max frequency maps to 1")
            // out-of-range inputs clamp to the endpoints
            #expect(sv.normalizedPosition(forFrequency: 10) == lo, "\(scale): below-min clamps to 0")
            #expect(sv.normalizedPosition(forFrequency: 40000) == hi, "\(scale): above-max clamps to 1")
            // strictly increasing with frequency
            let freqs: [Float] = [50, 200, 1000, 5000, 15000]
            let positions = freqs.map { sv.normalizedPosition(forFrequency: $0) }
            #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 },
                    "\(scale): position must increase with frequency")
        }
    }

    // frequencyTicks: mel/log share a fixed Hz set, linear uses 2 kHz strides, and both
    // are clipped to the visible [40, Nyquist] range.
    @Test func frequencyTicksRespectScaleAndRange() {
        let sv = SpectrogramGraph()   // Nyquist 22050
        sv.frequencyScale = .mel
        let mel = sv.frequencyTicks
        #expect(mel == [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000],
                "mel/log use the standard tick set within range")
        #expect(mel.allSatisfy { $0 >= sv.axisMinFrequency && $0 <= sv.axisMaxFrequency })

        sv.frequencyScale = .linear
        let linear = sv.frequencyTicks
        #expect(linear.first == 2000, "0 Hz is below the 40 Hz floor, so linear starts at 2 kHz")
        #expect(linear.allSatisfy { $0.truncatingRemainder(dividingBy: 2000) == 0 },
                "linear ticks are multiples of 2000")
        #expect(linear.allSatisfy { $0 <= sv.axisMaxFrequency }, "ticks stay within Nyquist")
    }

    // timeTickStep snaps the span to a "nice" step so the time axis gets ~5 labels.
    @Test func timeTickStepPicksNiceValues() {
        let sv = SpectrogramGraph()
        #expect(sv.timeTickStep(forSpan: 0) == 1, "zero span falls back to 1")
        #expect(sv.timeTickStep(forSpan: 6) == 2, "6s/5 = 1.2 → 2")
        #expect(sv.timeTickStep(forSpan: 2.5) == 0.5, "2.5s/5 = 0.5 → 0.5")
        #expect(sv.timeTickStep(forSpan: 25) == 5, "25s/5 = 5 → 5")
        #expect(sv.timeTickStep(forSpan: 1000) == 60, "huge spans cap at 60")
    }

    // historySeconds is columns × secondsPerColumn — the span of the time axis.
    @Test func historySecondsTracksColumns() {
        let sv = SpectrogramGraph()
        sv.secondsPerColumn = 0.01
        #expect(sv.historySeconds == 0, "no columns → zero span")
        sv.warpedData = Array(repeating: [Float](repeating: 0, count: 4), count: 10)
        #expect(abs(sv.historySeconds - 0.1) < 1e-9, "10 columns × 0.01s = 0.1s")
    }

    // spectrum is the newest intensity column; LTAS is the dB intensity of the mean linear
    // magnitude across all columns. both are empty until data exists.
    @MainActor @Test func spectrumAndLTASColumns() {
        let sv = SpectrogramGraph()
        #expect(sv.createSpectrumColumn().isEmpty, "no data → empty spectrum")
        #expect(sv.createLTASColumn().isEmpty, "no data → empty LTAS")

        let bins = 4
        let m1 = [Float](repeating: 0.1, count: bins)
        sv.appendColumn(magnitude: m1, intensity: sv.createIntensityColumn(from: m1))
        let m2 = [Float](repeating: 1.0, count: bins)
        let i2 = sv.createIntensityColumn(from: m2)
        sv.appendColumn(magnitude: m2, intensity: i2)

        // spectrum == newest intensity column
        #expect(sv.createSpectrumColumn() == i2, "spectrum should be the latest intensity column")

        // LTAS averages the linear magnitudes (mean of 0.1 and 1.0 = 0.55) then maps to dB
        let ltas = sv.createLTASColumn()
        #expect(ltas.count == bins, "LTAS has one value per frequency bin")
        #expect(ltas.allSatisfy { $0 >= 0 && $0 <= 1 }, "LTAS intensities are 0...1")
        let expected = sv.createIntensityColumn(from: [Float](repeating: 0.55, count: bins))
        #expect(zip(ltas, expected).allSatisfy { abs($0 - $1) < 1e-5 },
                "LTAS should equal the intensity of the mean magnitude")
    }
}

class MicManagerTestSuite {
    init() { print("Starting MicManager Test Suite.") }
    deinit { print("Ending MicManager Test Suite.") }

    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    // ringBuffer is a single-producer/single-consumer FIFO. A capacity-N buffer
    // holds N-1 items (one slot distinguishes full from empty), and writes wrap.
    @Test func ringBufferFifoWrapAndBounds() {
        let cap = 4
        let ring = RingBuffer<Int>(buffer: Array(repeating: 0, count: cap),
                                   writeIndex: ManagedAtomic<Int>(0),
                                   readIndex: ManagedAtomic<Int>(0),
                                   capacity: cap)
        #expect(ring.read() == nil, "empty buffer reads nil")
        #expect(ring.write(data: 1) == true)
        #expect(ring.write(data: 2) == true)
        #expect(ring.write(data: 3) == true)
        #expect(ring.write(data: 4) == false, "full at capacity - 1 items")
        #expect(ring.read() == 1, "FIFO order")
        #expect(ring.read() == 2)
        #expect(ring.write(data: 5) == true, "room again; this write wraps around")
        #expect(ring.read() == 3)
        #expect(ring.read() == 5, "wrapped value read back in order")
        #expect(ring.read() == nil, "drained buffer reads nil")
    }

    // bufferHandler must fan the same samples into BOTH ring buffers (disk + viz)
    // and store the mean magnitude into ampLevel.
    @Test func bufferHandlerFansOutAndComputesLevel() throws {
        let mic = MicManager(outputURL: tempURL("bh-test.caf"))
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let count: AVAudioFrameCount = 256
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        pcm.frameLength = count
        for i in 0..<Int(count) { pcm.floatChannelData![0][i] = Float(i) }

        mic.bufferHandler(pcm)

        for i in 0..<Int(count) {
            #expect(mic.ringBuffer.read() == Float(i), "disk buffer missing sample \(i)")
        }
        for i in 0..<Int(count) {
            #expect(mic.visualBuffer.read() == Float(i), "visual buffer missing sample \(i)")
        }
        // ramp 0..255 → mean magnitude = 127.5
        let level = Float(bitPattern: mic.ampLevel.load(ordering: .relaxed))
        #expect(abs(level - 127.5) < 0.01, "ampLevel should equal mean magnitude, got \(level)")
    }

    // an empty/zero-length buffer should be ignored (guard clauses), leaving the
    // ring buffers untouched.
    @Test func bufferHandlerIgnoresEmptyBuffer() throws {
        let mic = MicManager(outputURL: tempURL("bh-empty.caf"))
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        pcm.frameLength = 0   // no valid frames

        mic.bufferHandler(pcm)

        #expect(mic.visualBuffer.read() == nil, "no samples should have been written")
        #expect(mic.ringBuffer.read() == nil, "no samples should have been written")
    }
}

class StreamingManagerTestSuite {
    init() { print("Starting StreamingManager Test Suite.") }
    deinit { print("Ending StreamingManager Test Suite.") }

    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    // containsZeroRun flags a dropout only when there's a long run of EXACT zeros
    // (CoreAudio's zero-fill on a dropped input cycle); scattered zeros or real signal
    // must pass through.
    @Test func containsZeroRunDetectsDropouts() {
        let mic = MicManager(outputURL: tempURL("zero-run.caf"))
        let streaming = StreamingManager(source: mic)

        // a dropout: 64 consecutive exact zeros
        #expect(streaming.containsZeroRun([Float](repeating: 0, count: 64), minRun: 64),
                "64 consecutive zeros is a dropout")
        // 63 is below threshold
        #expect(!streaming.containsZeroRun([Float](repeating: 0, count: 63), minRun: 64),
                "63 zeros is below the run threshold")
        // zeros that never run consecutively are fine (real silence between samples)
        let alternating = (0..<200).map { $0 % 2 == 0 ? Float(0) : Float(1) }
        #expect(!streaming.containsZeroRun(alternating, minRun: 64),
                "non-consecutive zeros are not a dropout")
        // a real-ish signal has no long zero run
        let ramp = (1...500).map { Float($0) }
        #expect(!streaming.containsZeroRun(ramp, minRun: 64), "real signal has no zero run")
        // a zero run embedded inside real data is still caught
        var embedded = (1...100).map { Float($0) }
        embedded += [Float](repeating: 0, count: 64)
        embedded += (1...100).map { Float($0) }
        #expect(streaming.containsZeroRun(embedded, minRun: 64), "an embedded zero run is caught")
    }

    // preload the mic's visual buffer, run the manager briefly, and verify it slices the
    // stream into frames and feeds the renderer, which appends warped columns. also checks
    // secondsPerColumn is wired from hop/sampleRate.
    @MainActor @Test func liveStreamFeedsRenderer() async throws {
        let mic = MicManager(outputURL: tempURL("stream-test.caf"))
        let frameSize = 2048, hop = 512
        // non-zero ramp so the dropout filter (needs 64 consecutive zeros) never trips
        let total = frameSize + hop * 4
        for i in 0..<total { _ = mic.visualBuffer.write(data: Float(i) + 1) }

        let streaming = StreamingManager(source: mic)
        streaming.start(sampleRate: 44100)
        // timer fires every 20 ms; give the background work + MainActor appends time to land
        try await Task.sleep(nanoseconds: 300_000_000)
        streaming.stop()

        // consume() appends on the MainActor, and this test runs there
        #expect(!streaming.renderer.warpedData.isEmpty, "renderer should receive frames")
        #expect(streaming.renderer.warpedData.allSatisfy { $0.count == streaming.renderer.outputBins },
                "every warped column should have one value per output row")
        #expect(abs(streaming.renderer.secondsPerColumn - Double(hop) / 44100.0) < 1e-9,
                "secondsPerColumn should be hop / sampleRate")
    }

    // with no samples available, the renderer should receive nothing.
    @MainActor @Test func liveStreamEmptyBufferProducesNothing() async throws {
        let mic = MicManager(outputURL: tempURL("stream-empty.caf"))
        let streaming = StreamingManager(source: mic)
        streaming.start(sampleRate: 44100)
        try await Task.sleep(nanoseconds: 150_000_000)
        streaming.stop()

        #expect(streaming.renderer.warpedData.isEmpty, "no input should mean no columns")
    }
}
