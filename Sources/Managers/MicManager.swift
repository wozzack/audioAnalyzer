import AVFoundation
import CoreAudio
import AVFAudio
import Foundation
import AudioKit
import SwiftUI
import Atomics
import Dispatch
import Cocoa

/*
 
 audio thread > ring buffer > disk-writer thread
 real-time > shared memory > background queue
 captures samples > absorbs jitter > writes to file
 
 MAIN/UI [IN: ampLevel to level, OUT: meter value to swiftUI state]
 receives user instructions, perodically checks ampLevel, configures avaudioengine and allocates ring buffer, sets recordingFlag (atomic), updates display independent of audio rate
 AUDIO THREAD [IN: pcm buffers from tap, OUT: samples to ringBuffer, rms level to ampLevel]
    gets pcm buffers from the tap, WRITE into ring buffer, and calculate decibel level to store into atomic variable, no allocation, no locks, no gcd
 DISK WRITER [IN: samples from ring buffer, OUT: bytes to audioFile] - run on background thread, perodically READ samples from ring buffer, put into pcm buffer, and disk write to audioFile
 */

class MicManager: ObservableObject {
    // need avaudioengine tap to access the raw pcm buffer, which allows kme to run FFT on it
    // PCM buffer is the input for FFT, PCM is a flat array of floats representing amplitude at i time
    // need microphone permissions, info.plist key, app entitlements, error handling, memory cycling w. weak capture
    
    var engine: AVAudioEngine = AVAudioEngine()
    var audioFile: AVAudioFile = AVAudioFile()
    var ringBuffer: RingBuffer<Float>
    var visualBuffer: RingBuffer<Float>
    var drainBuffer: AVAudioPCMBuffer?
    var outputURL: URL
    
    // managed atomics
    let recordingFlag: ManagedAtomic<Bool>
    let ampLevel: ManagedAtomic<UInt32>
    let droppedBuffers: ManagedAtomic<Int>
    
    var writeTimer: DispatchSourceTimer?
    var writeQueue: DispatchQueue
    
    init(outputURL: URL, bufferSize: Int = 65536) {
        self.outputURL = outputURL
        // 1. allocate ring buffer
        ringBuffer = RingBuffer<Float>(
            buffer: Array(repeating: 0.0, count: bufferSize),
            writeIndex: ManagedAtomic<Int>(0),
            readIndex: ManagedAtomic<Int>(0),
            capacity: bufferSize // good sweet spot at 65536
        )
        
        visualBuffer = RingBuffer<Float>(
            buffer: Array(repeating: 0.0, count: bufferSize),
            writeIndex: ManagedAtomic<Int>(0),
            readIndex: ManagedAtomic<Int>(0),
            capacity: bufferSize // good sweet spot at 65536
        )
        // 2. initialize atomics
        recordingFlag = ManagedAtomic<Bool>(false)
        ampLevel = ManagedAtomic<UInt32>(Float(0.0).bitPattern)
        droppedBuffers = ManagedAtomic<Int>(0)
        // initialize queue
        writeQueue = DispatchQueue(label: "disk-writer", qos: .utility)
        // 3. create AVAudioFile for writing
        
    }
    /*
    startRecording: controls recordingFlag variable, starts the engine and creates timer here since cancelling is forever and it is more functionally clear to do it here vs in the initializer. sets the schedule for the timer, and creates event handler that calls the drainWrite method every interval, then starts the timer cycle.
     @: called by ContentView; calls reset(), bufferHandler()
     needs: engine, queue, and recordingFlag initialization
     gives: timer object scheduling and initialization, updates boolean of recordingFlag, starts engine and timer objects
     */
    func startRecording() async throws {
        // request mic permission; bail out if the user denies it (otherwise the
        // engine would crash trying to open an input it isnt allowed to use)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else {
            throw AudioManagerError.GenericFailure(funcName: "startRecording", reason: "microphone access was denied")
        }
        // 0. reject a re-entrant start,installing a second tap on an already recording engine hardcrashes
        guard !recordingFlag.load(ordering: .acquiring) else {
            throw AudioManagerError.GenericFailure(funcName: "startRecording", reason: "already recording")
        }
        // 1. set recordingFlag, use store cause its atomic
        recordingFlag.store(true, ordering: .releasing)
        // drop any samples left in the rings from a previous session so the stream
        // starts empty rather than replaying stale audio
        ringBuffer.reset()
        visualBuffer.reset()
        // 2. realize the input node and install the tap BEFORE starting the engine.
        // start() asserts (inputNode != nullptr) if no I/O node has been realized yet.
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // frameCapacity = sample rate * drain interval, multiplied by 2 for safety margin since drain interval isnt perfectly consistant
        drainBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 0.1 * 2)) ?? AVAudioPCMBuffer()
        // defensively clear any tap left over from a prior session that didnt stop
        // cleanly installTap asserts if a tap already exists on this bus
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.bufferHandler(buffer)
        }
        do {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        } catch {
            // undo the partial start so a later attempt isn't blocked by the flagnd doesnt leak the tap we just installed
            input.removeTap(onBus: 0)
            recordingFlag.store(false, ordering: .releasing)
            throw AudioManagerError.GenericFailure(funcName: "startRecording", reason: "failed to create avaudiofile")
        }
        // 3. now that the input node exists and has a tap, start the engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            recordingFlag.store(false, ordering: .releasing)
            throw error
        }

        // 3. create suspended timer with the associated writer queue
        let timer = DispatchSource.makeTimerSource(queue: writeQueue)
        // every 100ms it drains the buffer and writes to file
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        // weak self to prevent retaining cycle
        timer.setEventHandler { [weak self] in
            self?.drainWrite()
        }
        // store strong reference so it doesnt get deallocated
        writeTimer = timer
        // resume vs activate?
        timer.resume()
    }
    
    /*
    stopRecording: controls recordingFlag variable, stops the engine and deallocates timer object. schedules the flush drainWrite to the writeQueue via sync, if we did async it could return function before it actually fully executed the drainWrite method
     @: called by ContentView; calls drainWrite()
     needs: engine, timer, queue, and recordingFlag initialization
     gives: updates boolean of recordingFlag, stops engine and deallocates timer object
     */
    
    func stopRecording() {
        // 1. set recordingFlag
        recordingFlag.store(false, ordering: .relaxed)
        // 2. stop engine and remove tap
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // 3. stop timer
        writeTimer?.cancel()
        writeTimer = nil
        // 4. flush remaining data to disk
        writeQueue.sync { self.drainWrite() }
        // 5. deallocate class file and timer, remove tap, deallocate drainBuffer
        drainBuffer = nil
    }
    
    /*
     bufferHandler: takes in an PCMBuffer from the tap and writes it into the ring buffer. calls computeLevel and stores that in ampLevel. iterates through the ring buffer float array and performs write operation on the nth value in the ring buffer float array, setting it equal to the nth value in the given pcm buffer.
     @: called by startRecording(); calls write()
     needs: valid pcm buffer (does exist, with greater than zero frame lengths, and existing samples in the first channel array)
     gives: updates to dropped buffer count if failure, edits ring buffer, and stores computed level
     */
    func bufferHandler(_ pcm: AVAudioPCMBuffer) {
        // called from tap callback (audio thread)
        guard pcm.floatChannelData != nil, pcm.frameLength > 0
        else {
            return
        }
        guard pcm.floatChannelData?[0] != nil
        else {
            return
        }
        // compute level, atomic store to ampLevel
        ampLevel.store(computeLevel(buffer: pcm).bitPattern, ordering: .relaxed)
        // write samples from pcm buffer into ring buffer
        // let dropped = droppedBuffers.load(ordering: .relaxed)
        for i in 0..<pcm.frameLength {
            let sample = pcm.floatChannelData?[0][Int(i)] ?? 0.0
            if !ringBuffer.write(data: sample) {
                // droppedBuffers.store(dropped + 1, ordering: .relaxed)
                // increments by total dropped samples
                droppedBuffers.wrappingIncrement(ordering: .relaxed)
            }
            // fan out the same sample to the visualization buffer (separate reader
            // from the disk writer); dropping on full is fine for display
            _ = visualBuffer.write(data: sample)
        }
        
        // if failure (full or otherwise, need to call write from RingBuffer, droppedBuffers += 1
        // update ring write index
        // no allocation, no locks, no capes
    }
    /*
    drainWrite: when called by the disk timer periodically, it calls the read method from ringBuffer, then proceeds to prepare a pcm buffer to write to file. first we initialize the buffer with proper format, then create a pointer to the empty pcm buffers channels, then create a pointer to each nth value inside a single channel, and call on the ringBuffer read() method for 1024 values, ringBuffer.read will automactically increment one by one. then we create a new file with the data from the pcm buffer
     @: called by stopRecording() and startRecording(); calls read()
     needs: buffer inside ring buffer and droppedBuffers initialized
     gives: avaudiofile using the created avaudioformat and avaudiopcmbuffer
     */
    func drainWrite() {
        // called by disk timer (background queue)
        
        // read sample from ring buffer (it needs to iterate through the ring
        // set avaudio format, must match that of the avaudiofile
        
        guard let drainBuffer = drainBuffer
        else {
            return
        }
        
        // pack ring samples into pcm buffers
        // could also just allocate pcm buffer in startRecording... refill in here and set to nil in stopRecording
        // create pointer to iterate
        let channels = drainBuffer.floatChannelData
        let channelCount = drainBuffer.format.channelCount
        var framesWritten = 0

        // frameLength = number of valid audio frames stored in the buffer (data quantity)
        // frameCapacity = total number of audio frames the buffer can theoretically hold
        // channelCount = the total number of samples per frame (normally)
        
        // modify pcmBuffer via floatChannelData
        outerLoop: for frame in 0..<drainBuffer.frameCapacity {
            innerLoop: for channel in 0..<channelCount {
                // channels is a unsafemutablebufferpointer that we can iterate on
                // samples is the nth value pointer iterating through a single channel
                let samples = channels?[Int(channel)]
                // loop until either ringbuffer read returns nil or we filled pcmbuffer capacity
                guard let sample = ringBuffer.read()
                else { break outerLoop }
                samples?[Int(frame)] = sample
            }
            framesWritten += 1
        }
        drainBuffer.frameLength = AVAudioFrameCount(framesWritten)
        // need to convert samples into an AudioBufferList?
        
        // write to file
        do {
            try audioFile.write(from: drainBuffer)
            // audioFile = try AVAudioFile(url: outputURL, fromBuffer: drainBuffer)
        } catch {
            let dropped = droppedBuffers.load(ordering: .relaxed)
            print("drainWrite failed: \(error) (droppedBuffers: \(dropped))")
        }
        // note droppedBuffers in error message
    }
    
    // placeholder for actual ftt calculation
    func computeLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {return 0}
        let samples = channelData[0]
        let frameCount = Int(buffer.frameLength)
        
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += abs(samples[i])
        }
        return sum / Float(frameCount)
    }
}

class RingBuffer <T> {
    // used to be a swift array, which had issues because it has shared memory with the storage buffer and reference count (copy-on-write COW), which violates racing conditions. now is a continugous block of raw memory via unsafemutablepointer with count, type, and memory address
    private let buffer: UnsafeMutablePointer<T>
    let capacity: Int
    var writeIndex: ManagedAtomic<Int>
    var readIndex: ManagedAtomic<Int>

    init(buffer: [T], writeIndex: ManagedAtomic<Int>, readIndex: ManagedAtomic<Int>, capacity: Int) {
        precondition(buffer.count == capacity, "seed array must be exactly `capacity` elements")
        self.writeIndex = writeIndex
        self.readIndex = readIndex
        self.capacity = capacity
        // copy the seed array into the raw backing store so every slot is initialized
        self.buffer = UnsafeMutablePointer<T>.allocate(capacity: capacity)
        buffer.withUnsafeBufferPointer { src in
            self.buffer.initialize(from: src.baseAddress!, count: capacity)
        }
    }

    deinit {
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    /*
    reset: resets the indices of the ring buffer so that when we call a new tap, we arent reading previous session values. use atomic stores since no allocation nor locks allowed here.
     @: called by startRecording(); calls nothing
     needs: nothing really other than ring buffer initialized
     gives: the value 0 into the atomic read and write indices
    */
    func reset() {
        readIndex.store(0, ordering: .relaxed)
        writeIndex.store(0, ordering: .relaxed)
    }
    /*
     read: does an atomic load (no allocation) into unmutable variables reader and writer, does a check to see if empty via modulo operation. grabs data from unsafemutablepointer on reader index, then updates reader index += 1 via atomic store
     @: called by drainWrite(); calls nothing
     needs: initialized read and write indices and non-empty buffer
     gives: an updated readIndex and the data from the unsafemutablepointer
     */
    func read() -> T? {
        let reader = readIndex.load(ordering: .acquiring)
        let writer = writeIndex.load(ordering: .acquiring)
        // if empty
        if reader % capacity == writer {
            return nil
        }
        let data = buffer[reader]
        readIndex.store((reader + 1) % capacity, ordering: .releasing)
        return data
    }
    
    /*
     write: does an atomic load (no allocation) into unmutable variables reader and writer, does a check to see if full via modulo operation. writes data into unsafemutablepointer at writer index, then updates writer index += 1 via atomic store
     @: called by bufferHandler(); calls nothing
     needs: data, initialized read and write indices, and non full buffer for successful return
     gives: updated buffer with new data, and updated write index
     */
    func write(data: T) -> Bool {
        let reader = readIndex.load(ordering: .acquiring)
        let writer = writeIndex.load(ordering: .acquiring)
        // if full
        if (writer + 1) % capacity == reader {
            return false
        }
        buffer[writer] = data
        writeIndex.store((writer + 1) % capacity, ordering: .releasing)
        return true
    }
}
