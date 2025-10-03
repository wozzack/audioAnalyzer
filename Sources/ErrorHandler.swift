import AudioKit

import Foundation

import SwiftUI

// can call as unnamed parameter "errorHandler(error)"
public func errorHandler(_ error: Error) -> String{
    if let graphManagerError = error as? GraphManagerError {
        return "GraphManagerError in \(graphManagerError.errorDescription ?? "Unknown Type") \(graphManagerError.failureReason ?? "due to unknown")."
        
    } else if let canvasManagerError = error as? CanvasManagerError {
        return "CanvasManagerError in \(canvasManagerError.errorDescription ?? "Unknown Type") \(canvasManagerError.failureReason ?? "due to unknown")."
        
    } else if let audioManagerError = error as? AudioManagerError {
        return "AudioManagerError in \(audioManagerError.errorDescription ?? "Unknown Type") \(audioManagerError.failureReason ?? "due to unknown")."
    }
    else {
        return "Unhandled error."
    }
}

public enum GraphManagerError: LocalizedError {
    case GenericFailure(funcName: String, reason: String)
}

public enum CanvasManagerError: LocalizedError {
    case GenericFailure(funcName: String, reason: String)
}

public enum AudioManagerError: LocalizedError {
    case GenericFailure(funcName: String, reason: String)
}

// segment into per function error description for each error type


extension AudioManagerError {
    // contains type of error and function name
    public var errorDescription: String? {
        switch self {
        case .GenericFailure(let funcName, _):
            return "\(funcName)"
        }
    }
    // contains specific reason for failure
    public var failureReason: String? {
        switch self {
        case .GenericFailure(_, let reason):
            return "due to \(reason)."
        }
    }
}

extension CanvasManagerError {
    public var errorDescription: String? {
        switch self {
        case .GenericFailure(let funcName, _):
            return "\(funcName)"
        }
    }
    public var failureReason: String? {
        switch self {
        case .GenericFailure(_, let reason):
            return "due to \(reason)."
        }
    }
}

extension GraphManagerError {
    public var errorDescription: String? {
        switch self {
        case .GenericFailure(let funcName, _):
            return "\(funcName)"
        }
    }
    public var failureReason: String? {
        switch self {
        case .GenericFailure(_, let reason):
            return "due to \(reason)."
        }
    }
}


