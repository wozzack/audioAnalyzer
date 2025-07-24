/*
 really should be trying to shove a lot of the audioManager methods into here
 */

import AVFoundation

import AudioKit

import SwiftUI

func generalizedDownSampling(length: Int, file: AVAudioFile) throws -> [Float] {
  guard
    let buffer = AVAudioPCMBuffer(
      pcmFormat: file.processingFormat,
      frameCapacity: AVAudioFrameCount(file.length))
  else {
    throw AudioManagerError.GenericFailure
  }
  try file.read(into: buffer)
  guard let samples = buffer.floatChannelData
  else {
    throw AudioManagerError.GenericFailure
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
    return downSamples

  }
}
