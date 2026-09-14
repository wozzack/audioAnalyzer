import AudioKit

import Foundation

import SwiftUI

public protocol ManagerError: LocalizedError {
    var funcName: String { get }
    var reason: String { get }
    var domainName: String { get }
}

extension ManagerError {
    // contains domain, function name, and specific reason for failure
    public var errorDescription: String? {
        "\(domainName) error in \(funcName) due to \(reason)."
    }
    // contains specific reason for failure
    public var failureReason: String? {
        "due to \(reason)."
    }
}


public func errorHandler(_ error: Error) -> String {
    error.localizedDescription // single expression body
}

public struct PresentedError: Identifiable {
    public let id = UUID()
    public let message: String
}

@MainActor
public final class ErrorReporter: ObservableObject {
    @Published public var currentError: PresentedError?

    public init() {}

    public nonisolated func report(_ error: Error) {
        let message = errorHandler(error)
        Task { @MainActor in
            self.currentError = PresentedError(message: message)
        }
    }
}


public enum GraphManagerError: ManagerError {
    case GenericFailure(funcName: String, reason: String)

    public var domainName: String { "GraphManager" }
    public var funcName: String {
        switch self { case .GenericFailure(let funcName, _): return funcName }
    }
    public var reason: String {
        switch self { case .GenericFailure(_, let reason): return reason }
    }
}

public enum CanvasManagerError: ManagerError {
    case GenericFailure(funcName: String, reason: String)

    public var domainName: String { "CanvasManager" }
    public var funcName: String {
        switch self { case .GenericFailure(let funcName, _): return funcName }
    }
    public var reason: String {
        switch self { case .GenericFailure(_, let reason): return reason }
    }
}

public enum AudioManagerError: ManagerError {
    case GenericFailure(funcName: String, reason: String)

    public var domainName: String { "AudioManager" }
    public var funcName: String {
        switch self { case .GenericFailure(let funcName, _): return funcName }
    }
    public var reason: String {
        switch self { case .GenericFailure(_, let reason): return reason }
    }
}
