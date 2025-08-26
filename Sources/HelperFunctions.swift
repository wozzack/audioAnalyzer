/*
 really should be trying to shove a lot of the audioManager methods into here
 */

import AVFoundation

import AudioKit

import SwiftUI

import Waveform


func convertToAudioObject(s: String) throws -> AudioObject {
  guard let fileURL = Bundle.main.url(forResource: s, withExtension: "mp3")
            
            
  else {
    throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject")
  }
    let AVFile = try convertToAVAudioFile(s: s)
    // cant know duration until self is created
    let audio = AudioObject(url: fileURL, name: s, duration: AVFile.duration, file: AVFile)
  return audio
}



func convertToAVAudioFile(s: String) throws -> AVAudioFile {
  guard let fileURL = Bundle.main.url(forResource: s, withExtension: "mp3")
  else {
      throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile")
  }
  let file = try AVAudioFile(forReading: fileURL)
  return file
}

func minmaxDownSampling(length: Int, file: AVAudioFile) throws -> [(Float, Float)] {
  guard let buffer = AVAudioPCMBuffer(
    pcmFormat: file.processingFormat,
    frameCapacity: AVAudioFrameCount(file.length))

    else {
      throw AudioManagerError.GenericFailure(funcName: "minmaxDownSampling")
    }
    try file.read(into: buffer)
    let channelCount = Int(buffer.format.channelCount)
    // accounts for remaining fraction samples that can be accounted for by adding one more sample
    let totalSamples = Int(buffer.frameLength) / length + (Int(buffer.frameLength) % length == 0 ? 0 : 1)
    var downSamples: [(Float, Float)] = Array(repeating: (0.0, 0.0), count: totalSamples)
    for i in 0..<channelCount {
        let channelData = UnsafeBufferPointer(
            start: buffer.floatChannelData?[i],
            count: Int(buffer.frameLength))
        for j in stride(from: 0, to: Int(buffer.frameLength), by: length) {
            // splits single channel data into chunks of length n, and in that chunk searches for the highest and lowest value to append.
            // issue is that we need it for all channels, so we need to either average the min and max values across all channels or pick absolutely
            let chunkIndex = j / length // ???
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
