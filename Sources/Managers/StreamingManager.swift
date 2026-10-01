import Foundation

protocol StreamingConsumer: AnyObject {
    func configure(sampleRate: Double)
    func consume(frame: [Float])
}

// produces a steady stream of overlapping raw sample frames for consumers from micManager's visual buffer
class StreamingManager: ObservableObject {
    let renderer = SpectrogramView() // the live model canvas draws
    let source: MicManager // reads visualBuffer from micManager
    // serial queue provides lock-free safety since it can not be mutated by two pieces of code at the same time due to the queue, 2nd highest level of urgency as user is waiting on the result
    let queue = DispatchQueue(label: "streaming-manager",
                              qos: .userInitiated)
    // fires closure on the dispatch queue every x seconds when deployed
    var timer: DispatchSourceTimer?
    weak var consumer: StreamingConsumer? // avoid reference cycle with StreamingManager and consumer, can use consumer without keeping it alive
    var frameAccumulator: [Float] = [] // mutated with consume(), cleared by start() and stop()
    let frameSize = 2048, hopSize = 512 // per fft frame
    
    init(source: MicManager) {
        self.source = source
    }
    
    func start(sampleRate: Double, consumer: StreamingConsumer) {
        self.consumer = consumer
        consumer.configure(sampleRate: sampleRate)
        renderer.configure(sampleRate: sampleRate)
        queue.async { [weak self] in
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
    // micmanagers drain write but for streaming, turns raw and fast incoming samples into something that we can work with.
    private func packager() {
        // keep adding samples to the accumulator as they come in, 44100hz
        while let sample = source.visualBuffer.read() {
            frameAccumulator.append(sample)
        }
        // when there are enough samples in accumulator to create a whole frame...
        while frameAccumulator.count >= frameSize {
            let window = Array(frameAccumulator.prefix(frameSize))
            frameAccumulator.removeFirst(hopSize)
            consumer?.consume(frame: window)
        }
    }
    
    func stop() {
        timer?.cancel()
        timer = nil
        queue.async { [weak self] in
            self?.frameAccumulator.removeAll(keepingCapacity: true)
        }
    }
}


