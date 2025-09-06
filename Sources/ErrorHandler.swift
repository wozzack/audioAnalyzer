import AudioKit

import Foundation

import SwiftUI

// can call as unnamed parameter "errorHandler(error)"
public func errorHandler(_ error: Error) -> String{
    if let visualGraphError = error as? VisualGraphError {
        return "VisualGraphError in \(visualGraphError.errorDescription ?? "Unknown Type") \(visualGraphError.failureReason ?? "due to unknown")."
        
    } else if let graphManagerError = error as? GraphManagerError {
        return "GraphManagerError in \(graphManagerError.errorDescription ?? "Unknown Type") \(graphManagerError.failureReason ?? "due to unknown")."
        
    } else if let audioManagerError = error as? AudioManagerError {
        return "AudioManagerError in \(audioManagerError.errorDescription ?? "Unknown Type") \(audioManagerError.failureReason ?? "due to unknown")."
    }
    else {
        return "Unhandled error."
    }
}

public enum VisualGraphError: LocalizedError {
    case GenericFailure(funcName: String, reason: String)
}

public enum GraphManagerError: LocalizedError {
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

extension VisualGraphError {
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


/*

extension AudioManagerError: LocalizedError {
    public var errorDescription: String? {
        // if the error given by swift is of type X, then errorLogging switches on the error and returns a string.
        if let visualGraph = self as? VisualGraphError {
            switch visualGraph {
            case let .GenericFailure(funcName):
                return "VisualGraphError in \(funcName)."
            }
            
        } else if let graphError = self as? GraphManagerError {
            switch graphError {
            case let .GenericFailure(funcName):
                return "GraphManagerError in \(funcName)."
            }
            
        } else if let audioError = self as? AudioManagerError {
            switch audioError {
            case let .GenericFailure(funcName):
                return "AudioManagerError in \(funcName)."
            }
        }
        else {
            return "Unhandled error."
        }
    }
}
 */

