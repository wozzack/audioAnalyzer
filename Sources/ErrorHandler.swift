import AudioKit

import Foundation

import SwiftUI


public enum GraphManagerError: Error {
    case GenericFailure(funcName: String)

}
public enum VisualGraphError: Error {
    case GenericFailure(funcName: String)

}
public enum AudioManagerError: Error {
    case GenericFailure(funcName: String)

}

extension Error {
    func errorLogging() -> String {
        if let audioError = self as? AudioManagerError {
            switch audioError {
            case let .GenericFailure(funcName):
                return "[AudioManagerError] Error in \(funcName)."
            }
        } else if let graphError = self as? GraphManagerError {
            switch graphError {
            case let .GenericFailure(funcName):
                return "[GraphManagerError] Error in \(funcName)."
            }
        } else if let visualError = self as? VisualGraphError {
            switch visualError {
            case let .GenericFailure(funcName):
                return "[VisualGraphError] Error in \(funcName)."
            }
        
        }
        return "[UnknownError] An unknown error occurred."
    }
}

