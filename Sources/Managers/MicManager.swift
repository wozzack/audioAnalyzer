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
 MAIN/UI [IN: ampLevel to level, OUT: meter value to swiftUI state]
 receives user instructions, perodically checks ampLevel, configures avaudioengine and allocates ring buffer, sets recordingFlag (atomic), updates display independent of audio rate
 AUDIO THREAD [IN: pcm buffers from tap, OUT: samples to ringBuffer, rms level to ampLevel]
    gets pcm buffers from the tap, WRITE into ring buffer, and calculate decibel level to store into atomic variable, no allocation, no locks, no gcd
 DISK WRITER [IN: samples from ring buffer, OUT: bytes to audioFile] - run on background thread, perodically READ samples from ring buffer, put into pcm buffer, and disk write to audioFile
 */

class MicManager: ObservableObject {
    // need avaudioengine tap to access the raw pcm buffer, which allows kme to run FFT on it
    // PCM buffer is the input for FFT, PCM is a flat array of floats representing amplitude at i time
    // 1. Declare intent in Info.plist, 2. Request permission at runtime, 3. set up engine and install tap.
    //
    
    
    // need microphone permissions, info.plist key, app entitlements, error handling, memory cycling w. weak capture
    
    var engine: AVAudioEngine = AVAudioEngine()
    var audioFile: AVAudioFile = AVAudioFile()
    var ringBuffer: RingBuffer<Float>
    
    // managed atomics
    let recordingFlag: ManagedAtomic<Bool>
    let ampLevel: ManagedAtomic<UInt32>
    let droppedBuffers: ManagedAtomic<Int>
    
    var writeTimer: DispatchSourceTimer
    var writeQueue: DispatchQueue
    
    init(outputURL: URL, bufferSize: Int) {
        // 1. allocate ring buffer
        ringBuffer = RingBuffer<Float>()
        // 2. initialize atomics
        recordingFlag = ManagedAtomic<Boolean>(false)
        ampLevel = ManagedAtomic<UInt32>(Float(0.0).bitPattern)
        droppedBuffers = ManagedAtomic<Int>(0)
        // 3. create AVAudioFile for writing
        audioFile = try AVAudioFile(forWriting: outputURL, settings: "mp3")
        // 4. configure engine tap
        engine.inputNode.installTap(onBus: 0, bufferSize: 256, format: nil) { buffer, time in
            // ur mom
        }

        
    }
    // create timer here since cancelling is forever, plus it makes more sense to have it tied to startrecording instead of init in terms of function clarity
    func startRecording() {
        // 1. set recordingFlag, use store cause its atomic
        recordingFlag.store(true)
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
    
    func stopRecording() {
        // 1. set recordingFlag
        recordingFlag.store(false, ordering: .relaxed)
        // 2. stop engine
        engine.stop()
        // 3. stop timer
        writeTimer.cancel()
        // 4. flush remaining data to disk
        writeQueue = DispatchQueue(label: "disk-writer", qos: .utility)
        writeQueue.sync { self.drainWrite() }
        // 5. deallocate class file and timer
    }
    
    func bufferHandler(_ pcm: AVAudioPCMBuffer) {
        // called from tap callback (audio thread)
        
        // compute level, atomic store to ampLevel
        ampLevel.store(computeLevel(buffer: pcm).bitPattern, ordering: .relaxed)
        // write samples into buffer
        // if failure, droppedBuffers += 1
        // no allocation, no locks, no capes
    }
    
    func drainWrite() {
        // called by disk timer (background queue)
        
        // read samples from buffer
        // pack into pcm buffer
        // write to file
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
        var reader = readIndex.load()
        var writer = writeIndex.load()
        // if empty
        if reader % size == writer {
            return nil
        }
        var data = buffer[reader]
        readIndex.store((reader + 1) % size)
        return data
    }
    func write(data: T) -> Bool {
        var reader = readIndex.load()
        var writer = writeIndex.load()
        // if full
        if (writer + 1) % size == reader {
            return false
        }
        buffer[writer] = data
        writeIndex.store((writer + 1) % size)
        return true
    }
}
