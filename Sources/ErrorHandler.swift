import AudioKit

import Foundation

import SwiftUI


extension Error {
    func errorLogging() -> String {
        switch self {
        case let AudioManagerError.GenericFailure(funcName):
            return "[AudioManagerError] Error in \(funcName)."

        case let GraphManagerError.GenericFailure(funcName):
            return "[GraphManagerError] Error in \(funcName)."

        case let VisualGraphError.GenericFailure(funcName):
            return "[VisualProtocolError] Error in \(funcName)."
        }
    }
}
public enum GraphManagerError: Error {
    case GenericFailure(funcName: String)

}
public enum VisualGraphError: Error {
    case GenericFailure(funcName: String)

}
public enum AudioManagerError: Error {
    case GenericFailure(funcName: String)

}
