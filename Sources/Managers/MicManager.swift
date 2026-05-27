//
//  MicManager.swift
//  AudioDemo
//
//  Created by Kevin Truong on 4/2/26.
//


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
    let outputURL: URL
    
    // managed atomics
    let recordingFlag: ManagedAtomic<Bool>
    let ampLevel: ManagedAtomic<UInt32>
    let droppedBuffers: ManagedAtomic<Int>
    
    var writeTimer: DispatchSourceTimer?
    var writeQueue: DispatchQueue
    
    init(outputURL: URL, bufferSize: Int) throws {
        self.outputURL = outputURL
        // 1. allocate ring buffer
        ringBuffer = RingBuffer<Float>(
            buffer: Array(repeating: 0.0, count: bufferSize),
            writeIndex: ManagedAtomic<Int>(0),
            readIndex: ManagedAtomic<Int>(0),
            size: ManagedAtomic<Int>(bufferSize)
        )
        // 2. initialize atomics
        recordingFlag = ManagedAtomic<Bool>(false)
        ampLevel = ManagedAtomic<UInt32>(Float(0.0).bitPattern)
        droppedBuffers = ManagedAtomic<Int>(0)
        // initialize queue
        writeQueue = DispatchQueue(label: "disk-writer", qos: .utility)
        // 3. create AVAudioFile for writing
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]
        audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        // 4. configure engine tap
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, time in
            // ur mom
        }

        
    }
    /*
    startRecording: controls recordingFlag variable, starts the engine and creates timer here since cancelling is forever and it is more functionally clear to do it here vs in the initializer. sets the schedule for the timer, and creates event handler that calls the drainWrite method every interval, then starts the timer cycle.
     Needs: engine, queue, and recordingFlag initialization
     Gives: timer object scheduling and initialization, updates boolean of recordingFlag, starts engine and timer objects
     */
    func startRecording() {
        // 1. set recordingFlag, use store cause its atomic
        recordingFlag.store(true, ordering: .releasing)
        // 2. start engine, why though?
        try? engine.start()
        // 3. create suspended timer with the associated writer queue
        var timer = DispatchSource.makeTimerSource(queue: writeQueue)
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
     Needs: engine, timer, queue, and recordingFlag initialization
     Gives: updates boolean of recordingFlag, stops engine and deallocates timer object
     */
    
    func stopRecording() {
        // 1. set recordingFlag
        recordingFlag.store(false, ordering: .relaxed)
        // 2. stop engine
        engine.stop()
        // 3. stop timer
        writeTimer?.cancel()
        writeTimer = nil
        // 4. flush remaining data to disk
        writeQueue.sync { self.drainWrite() }
        // 5. deallocate class file and timer
    }
    
    /*
     bufferHandler: takes in an PCMBuffer from the tap and writes it into the ring buffer. calls computeLevel and stores that in ampLevel. iterates through the ring buffer float array and performs write operation on the nth value in the ring buffer float array, setting it equal to the nth value in the given pcm buffer.
     Needs: valid pcm buffer (does exist, with greater than zero frame lengths, and existing samples in the first channel array
     Gives: updates to dropped buffer count if failure, edits ring buffer, and stores computed level
     */
    func bufferHandler(_ pcm: AVAudioPCMBuffer) {
        // called from tap callback (audio thread)
        guard pcm.floatChannelData != nil, pcm.frameLength > 0
        else {
            return
        }
        guard let samples = pcm.floatChannelData?[0]
        else {
            return
        }
        // compute level, atomic store to ampLevel
        ampLevel.store(computeLevel(buffer: pcm).bitPattern, ordering: .relaxed)
        // write samples from pcm buffer into ring buffer
        let dropped = droppedBuffers.load(ordering: .relaxed)
        for i in 0..<pcm.frameLength {
            if !ringBuffer.write(data: pcm.floatChannelData?[0][Int(i)] ?? 0.0) {
                droppedBuffers.store(dropped + 1, ordering: .relaxed)
            }
        }
        // if failure (full or otherwise, need to call write from RingBuffer, droppedBuffers += 1
        // update ring write index
        // no allocation, no locks, no capes
    }
    /*
    drainWrite: when called by the disk timer periodically, it calls the read method from ringBuffer, then proceeds to prepare a pcm buffer to write to file. first we initialize the buffer with proper format, then create a pointer to the empty pcm buffers channels, then create a pointer to each nth value inside a single channel, and call on the ringBuffer read() method for 1024 values, ringBuffer.read will automactically increment one by one. then we create a new file with the data from the pcm buffer
     Needs: buffer inside ring buffer and droppedBuffers initialized
     Gives: avaudiofile using the created avaudioformat and avaudiopcmbuffer
     */
    
    func drainWrite() {
        // called by disk timer (background queue)
        
        // read sample from ring buffer (it needs to iterate through the ring
        // set avaudio format, must match that of the avaudiofile
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)
        else {
            return
        }
        // pack ring samples into pcm buffers
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)
        pcmBuffer?.frameLength = AVAudioFrameCount()
        // create pointer to iterate
        let channels = pcmBuffer?.floatChannelData
        let channelCount = pcmBuffer?.format.channelCount ?? 0
        
        // ??? samples is a 1d array not 2d... and it doesnt exist outside the loop ;/
        // i need to edit pcmBuffer via floatChannelData
        for channel in 0..<channelCount {
            // channels is a unsafemutablebufferpointer that we can iterate on
            // samples is the nth value pointer iterating through a single channel
            let samples = channels?[Int(channel)]
            for frame in 0..<1024 {
                samples?[frame] = ringBuffer.read() ?? 0.0
            }
        }
        // need to convert samples into an AudioBufferList
        
        // write to file
        do {
            audioFile = try AVAudioFile(url: outputURL, fromBuffer: pcmBuffer!)
        } catch {
            let dropped = droppedBuffers.load(ordering: .relaxed)
            print("drainWrite failed: \(error) (droppedBuffers: \(dropped))")
        }
        // note droppedBuffers in error message
    }
    
    func setup() {
        
        // set up avaudioengine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        // attach tap to capture mic buffers, maybe use avaudiosink instead...
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            let level = self.computeLevel(buffer: buffer)
            
            // basically UI need priority over all other processes, so it sends it to the main thread to be done without dependence on other processes. there exists a thread thats very fast for audio processing, but it aint no main thread
            let audioUIQueue = DispatchQueue(label: "audioUI")
            audioUIQueue.async {
                self.ampLevel.store(level.bitPattern, ordering: .relaxed)
            }
            
            audioUIQueue.sync {
                _ = Float(bitPattern: self.ampLevel.load(ordering: .relaxed))
            }
        }
        
        // try? engine.start()
    }
    
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
    var buffer: [T] = []
    var writeIndex: ManagedAtomic<Int>
    var readIndex: ManagedAtomic<Int>
    var size: ManagedAtomic<Int>
    
    init(buffer: [T], writeIndex: ManagedAtomic<Int>, readIndex: ManagedAtomic<Int>, size: ManagedAtomic<Int>) {
        self.buffer = buffer
        self.writeIndex = writeIndex
        self.readIndex = readIndex
        self.size = size
    }
    
    func read() -> T? {
        let reader = readIndex.load(ordering: .relaxed)
        let writer = writeIndex.load(ordering: .relaxed)
        let capacity = size.load(ordering: .relaxed)
        // if empty
        if reader % capacity == writer {
            return nil
        }
        let data = buffer[reader]
        readIndex.store((reader + 1) % capacity, ordering: .relaxed)
        return data
    }
    func write(data: T) -> Bool {
        let reader = readIndex.load(ordering: .relaxed)
        let writer = writeIndex.load(ordering: .relaxed)
        let capacity = size.load(ordering: .relaxed)
        // if full
        if (writer + 1) % capacity == reader {
            return false
        }
        buffer[writer] = data
        writeIndex.store((writer + 1) % capacity, ordering: .relaxed)
        return true
    }
}
