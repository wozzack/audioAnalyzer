/*
 really should be trying to shove a lot of the audioManager methods into here
 */

import AVFoundation

import AudioKit

import SwiftUI

import Waveform


func convertToAudioObject(s: String) throws -> AudioObject {
  guard let fileURL = Bundle.main.url(forResource: s, withExtension: "wav")
            
            
  else {
    throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject")
  }
    let AVFile = try convertToAVAudioFile(s: s)
    // cant know duration until self is created
    let audio = AudioObject(url: fileURL, name: s, duration: AVFile.duration, file: AVFile)
  return audio
}


func convertToAVAudioFile(s: String) throws -> AVAudioFile {
  guard let fileURL = Bundle.main.url(forResource: s, withExtension: "wav")
  else {
      throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile")
  }
  let file = try AVAudioFile(forReading: fileURL)
    //print("File FCD: \(file.floatChannelData()  as Any)")
  return file
}

func minmaxDownSampling(length: Int, file: AVAudioFile) throws -> [(Float, Float)] {
    
    // var file = try makeDummyAVAudioFile() // not the issue
    // print(file.floatChannelData() as Any)
    print("Reached minmaxsampling...")
    print("About to allocate buffer.")
    /*
    guard let buffer = AVAudioPCMBuffer(
        //pcmFormat: format,
        pcmFormat: file.processingFormat,
        // literally going to kill myself this is stupid
        frameCapacity: AVAudioFrameCount(file.length)) // 5 seconds max
     */
    guard let buffer = try AVAudioPCMBuffer(file: AVAudioFile(forReading: file.url))
    else {
        print("Failed to allocate buffer.")
        throw AudioManagerError.GenericFailure(funcName: "minmaxDownSampling buffer allocation failed")
    }
    do {
        print("File processing format: \(file.processingFormat)")
        print("File length: \(file.length)")
        print("Buffer frame length: \(buffer.frameLength)")
        print("Buffer frame capacity: \(buffer.frameCapacity)")
        print("Buffer float channel data: \(buffer.floatChannelData as Any)")
        // what the fuck is happening here, avfaudio error -50
        /*
        do {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(file.length))
            if buffer.floatChannelData == nil {
                print("Float channel data is nil.")
            }
            print("Buffer frame length: \(buffer.frameLength)")
        } catch {
            print("Error reading audio files: \(error)")
        }
         */
        guard buffer.floatChannelData != nil
        else {
            let _: [(Float, Float)] = (0..<50).map { i in
                let x = Float(i) / 50.0
                let minVal = sin(2 * .pi * x)
                let maxVal = minVal + 0.2 // offset for visualization
                return (minVal, maxVal)
            }
            //print(buffer.floatChannelData)
            //return [(1.0, 1.0), (20.0, 20.0), (10.0, 10.0), (100, 100)] // temp fix
            throw VisualGraphError.GenericFailure(funcName: "buffer floatChannelData is nil")
        }
    } catch {
            //throw AudioManagerError.GenericFailure(funcName: "readintobuffer error")
    }
    print("Reached downsampling algorithm.")
    let channelCount = Int(buffer.format.channelCount)
    //for remaining fraction samples that can be accounted for by adding one more sample
    let totalSamples = Int(buffer.frameLength) / length + (Int(buffer.frameLength) % length == 0 ? 0 : 1)
    var downSamples: [(Float, Float)] = Array(repeating: (0.0, 0.0), count: totalSamples)
    for channel in 0..<channelCount {
        let channelData = UnsafeBufferPointer(
            start: buffer.floatChannelData?[channel],
            count: Int(buffer.frameLength))
        for j in stride(from: 0, to: Int(buffer.frameLength), by: length) {
            // splits single channel data into chunks of length n, and in that chunk searches for the highest and lowest value to append.
            // issue is that we need it for all channels, so we need to either average the min and max values across all channels or pick absolutely
            let chunkIndex = j / length
            let chunk = channelData[j..<min(j + length, Int(buffer.frameLength))]
            let minSample = chunk.min() ?? 0
            let maxSample = chunk.max() ?? 0
            downSamples[chunkIndex].0 += minSample / Float(channelCount)
            downSamples[chunkIndex].1 += maxSample / Float(channelCount)
        }
    }
    return downSamples
  // downSamples is an array of tuples that represent the min and max samples
}

func makeDummyAVAudioFile() throws -> AVAudioFile {
    let sampleRate: Double = 44100
    let frameCount: AVAudioFrameCount = 300
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount

    let channelData = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        channelData[i] = sin(2 * .pi * Float(i) / Float(frameCount)) // Sine wave
    }

    // Save buffer to a temporary file for AVAudioFile
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dummy.wav")
    let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
    try audioFile.write(from: buffer)
    return try AVAudioFile(forReading: tempURL)
}

func averageDownSampling(length: Int, file: AVAudioFile) throws -> [Float] {
  guard
    let buffer = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat,
      frameCapacity: AVAudioFrameCount(file.length))
  else {
      throw AudioManagerError.GenericFailure(funcName: "generalizedDownSampling")
  }
  try file.read(into: buffer)
  guard let samples = buffer.floatChannelData
  else {
      throw AudioManagerError.GenericFailure(funcName: "generalizedDownSampling")
  }

  let channelCount = Int(buffer.format.channelCount)

  // one dimensional once we apply averaging function
  var downSamples: [Float] = []

  for i in 0..<channelCount {
    let channelData = UnsafeBufferPointer(
      start: samples[i],
      count: Int(buffer.frameLength))
    for j in stride(from: 0, to: Int(buffer.frameLength), by: length) {
      downSamples[j] += channelData[j] / Float(channelCount)
    }
    // downSamples is an 1D array of float values that represent the averaged samples
  }
    return downSamples
}
