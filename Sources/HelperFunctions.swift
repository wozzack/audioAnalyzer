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
    // cant know duration until self is created
    let audio = AudioObject(url: fileURL, name: s, duration: , file: convertToAVAudioFile(s: s))
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
func generalizedDownSampling(length: Int, file: AVAudioFile) throws -> [Float] {
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
    return downSamples

  }
}
