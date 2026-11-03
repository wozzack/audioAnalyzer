import Foundation
import Atomics

protocol StreamingConsumer: AnyObject {
    func configure(sampleRate: Double)
    func consume(frame: [Float])
}

// produces a steady stream of overlapping raw sample frames for consumers from micManager's visual buffer
class StreamingManager: ObservableObject {
    let renderer = SpectrogramGraph() // the live model canvas draws
    let source: MicManager // reads visualBuffer from micManager
    // serial queue provides lock-free safety since it can not be mutated by two pieces of code at the same time due to the queue, 2nd highest level of urgency as user is waiting on the result
    let queue = DispatchQueue(label: "streaming-manager",
                              qos: .userInitiated)
    // fires closure on the dispatch queue every x seconds when deployed
    var timer: DispatchSourceTimer?
    // weak var consumer: StreamingConsumer? // avoid reference cycle with StreamingManager and consumer, can use consumer without keeping it alive
    var frameAccumulator: [Float] = [] // mutated with consume(), cleared by start() and stop()
    var frameSize: Int { renderer.config.frameSize }
    var hopSize: Int { renderer.config.hopSize }
    
    init(source: MicManager) {
        self.source = source
    }
    /*
     start: caller for the packager. runs configuration setting on SpectrogramGraph() object then assigns off of the main thread onto the streaming queue we call to clear the accumulator before we resume the timer, which is allocated here and set to start immediately once resumed every 1/50 of a second and set to call the packager
     @: called by startLive(); calls configure() and packager()
     needs: sampleValue, dispatchQueue initialization
     gives: the queue a task to do, along with configuration of the renderer (SpectrogramGraph())
     */
    func start(sampleRate: Double) {
        // do on queue to avoid race condition since it does a write, is called before we resume timer (which is by default suspended)
        queue.async { [weak self] in
            self?.renderer.configure(sampleRate: sampleRate)
            self?.renderer.secondsPerColumn = Double(self?.hopSize ?? 0) / sampleRate
            self?.frameAccumulator.removeAll(keepingCapacity: true)
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        // calls and checks visual buffer 50 times a second
        t.schedule(deadline: .now(), repeating: 0.02)
        t.setEventHandler { [weak self] in
            self?.packager()
        }
        timer = t
        t.resume()
    }
    /*
     packager: micmanagers drain write but for streaming, turns raw and fast incoming samples into something that we can work with. while there is a sample to read, will append to the accumulator. once acculumator is full, consume the created window array and remove hopSize first elements in the accumulator (remember there has to be overlap)
     @: called by start(); calls consume() and read()
     needs: sample to read (or technically it doesnt)
     gives: a window for SpectrogramGraph() to consume, an updated accumulator buffer
     */
    func packager() {
        // ...
        if source.visualDiscontinuity.exchange(false, ordering: .acquiringAndReleasing) {
            discardPendingVisualStream()
            return
        }
        // keep adding samples to the accumulator as they come in, 44100hz
        while let sample = source.visualBuffer.read() {
            frameAccumulator.append(sample)
        }
        
        if source.visualDiscontinuity.exchange(false, ordering: .acquiringAndReleasing) {
            discardPendingVisualStream()
            return
        }
        
        // when there are enough samples in accumulator to create a whole frame...
        while frameAccumulator.count >= frameSize {
            let window = Array(frameAccumulator.prefix(frameSize)) // whats passed as "frame" or "timeframe" in graphmanager functions
            // skips windows that have a dropped input cycle ("HALC … skipping cycle due to overload")
            if containsZeroRun(window, minRun: 64) {
                frameAccumulator.removeAll(keepingCapacity: true)
                break
            }
            frameAccumulator.removeFirst(hopSize)
            renderer.consume(frame: window)
        }
    }
    
    func discardPendingVisualStream() {
        frameAccumulator.removeAll(keepingCapacity: true)
        
        for _ in 0..<source.visualBuffer.capacity {
            guard source.visualBuffer.read() != nil
            else { break }
        }
    }
    func containsZeroRun(_ samples: [Float], minRun: Int) -> Bool {
        var run = 0
        for s in samples {
            if s == 0 {
                run += 1
                if run >= minRun { return true }
            } else {
                run = 0
            }
        }
        return false
    }
    /*
     stop: deallocates the timer and assigns clearing task to queue async-ly
     @: called by stopLive(); calls nothing
     needs: nothing
     gives: deallocated timer, emptied (capacity retained), updated accumulator
     */
    func stop() {
        timer?.cancel()
        timer = nil
        renderer.scaleEpoch.wrappingIncrement(ordering: .relaxed)
        queue.async { [weak self] in
            self?.frameAccumulator.removeAll(keepingCapacity: true)
        }
    }
    
    /*
     setFrequencyScale: for live modification of the spectrogram to fit a new scaling mode (linear, mel, log). rebuilds frequency mapping and clears cache.
     @: called by setFrequencyScale() (yes same name but in CanvasManager trust; calls rebuildFrequencyMap() and clearSpectrogramCaches()
     needs: nothing
     gives: new frequency map, cleared spectrogram cache
     */
    func setFrequencyScale(_ scale: FrequencyScale) {
        queue.async { [weak self] in
            self?.renderer.scaleEpoch.wrappingIncrement(ordering: .relaxed)
            self?.renderer.rebuildFrequencyWarp(scale: scale)
        }
        Task { @MainActor [weak self] in
            self?.renderer.frequencyScale = scale
            self?.renderer.clearSpectrogramCaches()
        }
    }
}


