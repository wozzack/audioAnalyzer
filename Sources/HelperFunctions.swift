/*
 really should be trying to shove a lot of the audioManager methods into here
 */

import AVFoundation

import AudioKit

import SwiftUI

import Waveform


func convertToAudioObject(s: String) throws -> AudioObject {
    // confirm it exists in our app bundle, want to be general for any file type
    // i want it to be able to auto detect file type by given string, will search in bundle and if multiple exists of diifferent file type, ask to specify file type in the string itself
    // given "misato.mp3", it will search for misato.mp3 in the bundle and if it exists, return the file URL for that resource
    let regexFilePattern = try Regex("[a-zA-Z0-9_]+\\.(wav|flac|mp3|m4a|aac)$")
    
    guard s.contains(regexFilePattern)
    else {
        throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject", reason: "Invalid string input.")
    }
        // locate file type and then extract the file name and extension from the string
    let fileExtension = String(s.split(separator: ".")[1])
    let fileName = String(s.split(separator: ".")[0])
    // if confirms to pattern, then start processing the string to extract the file name and extension
    guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    else {
        throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject", reason: "Failed to find file URL for resource \(s).wav")
    }
    do {
        let AVFile = try AVAudioFile(forReading: fileURL)
        let audio = AudioObject(url: fileURL, name: s, duration: AVFile.duration, file: AVFile)
        return audio
    } catch {
        throw AudioManagerError.GenericFailure(funcName: "convertToAudioObject", reason: "failed to create AVAudioFile for resource \(s).wav")
    }
}


func convertToAVAudioFile(s: String) throws -> AVAudioFile {
    let regexFilePattern = "[a-zA-Z0-9_]+\\.(wav|flac|mp3|m4a|aac)$"
    guard s.contains(regexFilePattern)
    else {
        throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile", reason: "Invalid string input.")
    }
        // locate file type and then extract the file name and extension from the string
    let fileExtension = String(s.split(separator: ".")[1])
    let fileName = String(s.split(separator: ".")[0])
    // want to be general for any file type
    guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension)
    else {
        throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile", reason: "failed to find file URL for resource \(s).wav")
    }
    do {
        let file = try AVAudioFile(forReading: fileURL)
        return file
    } catch {
        throw AudioManagerError.GenericFailure(funcName: "convertToAVAudioFile", reason: "failed to create AVAudioFile for resource \(s).wav")
    }
}

func minmaxDownSampling(length: Int, file: AVAudioFile) throws -> [(Float, Float)] {
    guard let buffer = try AVAudioPCMBuffer(file: AVAudioFile(forReading: file.url)), buffer.floatChannelData != nil
    else {
        throw GraphManagerError.GenericFailure(funcName: "minmaxDownSampling", reason: "failed to create AVAudioPCMBuffer from AVAudioFile")
    }
    
    do {
        // changed to below framelength for error system checking
        guard buffer.floatChannelData != nil, buffer.frameLength > 0
        else {
            throw GraphManagerError.GenericFailure(funcName: "mixmaxDownSampling", reason: "buffer has no floatChannelData or frameLength is invalid")
        }
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
        // downSamples is an array of tuples that represent the min and max samples
        return downSamples
        // end of do clause
    } catch {
        throw GraphManagerError.GenericFailure(funcName: "minmaxDownSampling", reason: "failed during downsampling process for AVAudioFile")
    }
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
