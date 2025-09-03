import AudioKit

import Foundation

import SwiftUI


public enum VisualGraphError: Error {
    case GenericFailure(funcName: String)
}

public enum GraphManagerError: Error {
    case GenericFailure(funcName: String)
}

public enum AudioManagerError: Error {
    case GenericFailure(funcName: String)
}


extension Error {
    func errorLogging() -> String {
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

