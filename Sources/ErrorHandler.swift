import AudioKit

import Foundation

import SwiftUI

// can call as unnamed parameter "errorHandler(error)"
public func errorHandler(_ error: Error) -> String{
    if let visualGraphError = error as? VisualGraphError {
        return "VisualGraphError in \(visualGraphError.errorDescription ?? "unhandled error")."
        
    } else if let graphManagerError = error as? GraphManagerError {
        return "GraphManagerError in \(graphManagerError.errorDescription ?? "unhandled error")."
        
    } else if let audioManagerError = error as? AudioManagerError {
        return "AudioManagerError in \(audioManagerError.errorDescription ?? "unhandled error")."
    }
    else {
        return "Unhandled error."
    }
}

public enum VisualGraphError: LocalizedError {
    case GenericFailure(funcName: String)
}

public enum GraphManagerError: LocalizedError {
    case GenericFailure(funcName: String)
}

public enum AudioManagerError: LocalizedError {
    case GenericFailure(funcName: String)
}


extension AudioManagerError {
    public var errorDescription: String? {
        switch self {
        case .GenericFailure(let funcName):
            return "AudioManagerError in \(funcName)."
        }
    }
}

extension GraphManagerError {
    public var errorDescription: String? {
        switch self {
        case .GenericFailure(let funcName):
            return "GraphManagerError in \(funcName)."
        }
    }
}

extension VisualGraphError {
    public var errorDescription: String? {
        switch self {
        case .GenericFailure(let funcName):
            return "VisualGraphError in \(funcName)."
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

