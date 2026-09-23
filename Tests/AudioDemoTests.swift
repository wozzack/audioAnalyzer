
import Testing
import SwiftUI
import AudioKit
import AVFoundation
import Foundation
import Atomics

@testable import AudioDemo

// records frames handed to it by StreamingManager. Thread-safe because the
// streaming queue calls `consume` on a background thread while the test reads.
final class MockStreamingConsumer: StreamingConsumer {
    private let lock = NSLock()
    private var storage: [[Float]] = []
    private(set) var configuredSampleRate: Double?

    var frames: [[Float]] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func configure(sampleRate: Double) {
        configuredSampleRate = sampleRate
    }

    func consume(frame: [Float]) {
        lock.lock()
        storage.append(frame)
        lock.unlock()
    }
}

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
            #expect(canvasManager.visualModel is WaveformView, "visualModel is of wrong type")
            #expect(canvasManager.visualModel!.dsData != nil, "dsData is nil")
        } catch {
            throw CanvasManagerError.GenericFailure(funcName: "changeGraph", reason: "failed to change visualModel and it's properties correctly.")
        }
        
        do {
            try canvasManager.changeGraph(newGraph: .spectrogram, file: testFile2.file)
            #expect(canvasManager.visualModel is SpectrogramView, "visualModel is of wrong type")
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
            try canvasManager.visualModel?.processAudio(AVFile: testAudioObject.file)
            // check that they are not nil
            #expect(canvasManager.visualModel?.rawData != nil)
            // dsData is type-erased through `any VisualGraph`, so cast to the concrete type
            let dsData = (canvasManager.visualModel as? WaveformView)?.dsData
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
            throw CanvasManagerError.GenericFailure(funcName: "processAudio", reason: "failed to process audio for testAudioObject1")
        }
        
        // failure due to mismatched files
        do {
            try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject2.file)
        } catch let error {
            #expect(error is GraphManagerError)
        }
        
        do {
            try canvasManager.visualModel?.processAudio(AVFile: testAudioObject2.file)
            try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject2.file)
            // check that they are not nil
            #expect(canvasManager.visualModel?.rawData != nil)
            let dsData = (canvasManager.visualModel as? WaveformView)?.dsData
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
            throw CanvasManagerError.GenericFailure(funcName: "processAudio", reason: "failed to process audio for testAudioObject2")
        }
    }
    
    @MainActor @Test func waveformDrawing() throws {
        let audioManager = AudioManager()
        let canvasManager = CanvasManager()
        let testAudioObject = try convertToAudioObject(s: "misato.mp3")
        try audioManager.addToPlaylist(audio: testAudioObject)
        try audioManager.loadAudio(audio: audioManager.playlist[0])
        try canvasManager.changeGraph(newGraph: .waveform, file: testAudioObject.file)
        try canvasManager.visualModel?.processAudio(AVFile: testAudioObject.file)
        let displaySize = CGRect(x: 0, y: 0, width: 300, height: 600)
        
        // what do i want to check for in the pathobject?
        
        let pathObject = try canvasManager.visualModel?.drawGraph(rect: displaySize, color: .blue, lineWidth: 1.0)

        #expect(pathObject != nil)

    }

    // qa 440 Hz sine, run through one column of the live spectrogram path
    // (frequencyMapping -> frameDFT -> sliceWarp), should peak on the mel row
    // that maps back to ~440 Hz. This mirrors what makeColumn will do per frame.
    @Test func liveColumnSineMapping() throws {
        let sampleRate = 44100.0
        let frameSize = 1024
        let testFreq = 440.0

        let sv = SpectrogramView()
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
        let linear = try sv.frameDFT(timeFrame: frame)          // 513 linear magnitudes
        let column = sv.sliceWarp(spectrum: linear, map: map)   // outputRows warped values

        #expect(column.count == outputRows, "warped column should have one value per output row")

        // brightest row -> convert back to Hz and check it lands near 440
        guard let peakRow = column.indices.max(by: { column[$0] < column[$1] }) else {
            throw GraphManagerError.GenericFailure(funcName: "liveColumnSineMapping", reason: "empty warped column")
        }
        let peakFreq = sv.targetFrequency(row: peakRow, totalRows: outputRows, scale: .mel,
                                          maxFrequency: Float(sampleRate / 2), minFrequency: 40)

        // FFT bin resolution is 44100/1024 ≈ 43 Hz, so allow ~one bin of slack
        #expect(abs(peakFreq - Float(testFreq)) < 60,
                "expected peak near \(testFreq) Hz, got \(peakFreq) Hz at row \(peakRow)")
    }

    // a high-frequency tone must map to a high mel row. This fails if numBins is
    // derived from outputRows instead of frameSize (which clamps high bins onto one row).
    @Test func liveColumnHighFrequencyMapping() throws {
        let sampleRate = 44100.0
        let frameSize = 1024
        let testFreq = 15000.0

        let sv = SpectrogramView()
        let outputRows = sv.outputBins
        let frame: [Float] = (0..<frameSize).map { i in
            Float(sin(2 * Double.pi * testFreq * Double(i) / sampleRate))
        }
        let map = sv.frequencyMapping(scale: .mel, sampleRate: sampleRate, frameSize: frameSize,
                                      outputRows: outputRows, minFrequency: 40,
                                      maxFrequency: Float(sampleRate / 2))
        let linear = try sv.frameDFT(timeFrame: frame)
        let column = sv.sliceWarp(spectrum: linear, map: map)

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
        let sv = SpectrogramView()
        #expect(sv.frequencyMap == nil, "no map before configure")
        sv.configure(sampleRate: 44100)
        #expect(sv.frequencyMap != nil, "configure should build the frequency map")

        let column = try sv.createColumn(from: [Float](repeating: 0, count: 1024))
        #expect(column.count == sv.outputBins, "column should have one value per output row")
    }

    // appendColumn scrolls: the rolling window must never exceed rollingWidth.
    @MainActor @Test func appendColumnRespectsRollingWidth() {
        let sv = SpectrogramView()
        let column = [Float](repeating: 0.5, count: sv.outputBins)
        for _ in 0..<(sv.rollingWidth + 50) {
            sv.appendColumn(column: column)
        }
        #expect(sv.warpedData.count == sv.rollingWidth,
                "rolling window should cap at rollingWidth, got \(sv.warpedData.count)")
    }

    // the mel map should be well-formed: right length, monotonic bins, valid weights.
    @Test func frequencyMapIsWellFormed() {
        let sv = SpectrogramView()
        let map = sv.frequencyMapping(scale: .mel, sampleRate: 44100, frameSize: 1024,
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

    // preload the mic's visual buffer, run the manager briefly, and verify it
    // slices the stream into overlapping fixed-size frames delivered to the consumer.
    @Test func deliversOverlappingFramesToConsumer() async throws {
        let mic = MicManager(outputURL: tempURL("stream-test.caf"))
        // enough for a handful of 1024-frames at hop 512
        let total = 1024 + 512 * 3
        for i in 0..<total { _ = mic.visualBuffer.write(data: Float(i)) }

        let consumer = MockStreamingConsumer()
        let streaming = StreamingManager(source: mic)
        streaming.start(sampleRate: 44100, consumer: consumer)
        // timer fires every 20 ms; give it room to drain everything
        try await Task.sleep(nanoseconds: 200_000_000)
        streaming.stop()

        let frames = consumer.frames
        #expect(consumer.configuredSampleRate == 44100, "consumer should be configured on start")
        #expect(!frames.isEmpty, "consumer should receive at least one frame")
        #expect(frames.allSatisfy { $0.count == 1024 }, "every frame must be frameSize long")
        // FIFO integrity: first frame is samples 0...1023
        if let first = frames.first {
            #expect(first.first == 0)
            #expect(first.last == 1023)
        }
        // 50% overlap: the second frame starts hopSize (512) later
        if frames.count >= 2 {
            #expect(frames[1].first == 512, "second frame should start one hop later")
        }
    }

    // with no samples available, the consumer should receive nothing.
    @Test func deliversNothingWhenBufferEmpty() async throws {
        let mic = MicManager(outputURL: tempURL("stream-empty.caf"))
        let consumer = MockStreamingConsumer()
        let streaming = StreamingManager(source: mic)
        streaming.start(sampleRate: 44100, consumer: consumer)
        try await Task.sleep(nanoseconds: 100_000_000)
        streaming.stop()

        #expect(consumer.frames.isEmpty, "no input should mean no frames")
    }
}

