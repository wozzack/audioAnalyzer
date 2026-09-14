import AudioKit

import Foundation

import SwiftUI

// MARK: - Shared error contract

/// Every manager error carries the same two pieces of data (which function
/// failed, and why) plus a human-readable domain name. Conforming to this
/// protocol gives each error type its `errorDescription`/`failureReason` for
/// free via the default implementations below, so the boilerplate lives in
/// exactly one place.
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

// MARK: - Error reporting

/// Produces a user-facing message for any error. `ManagerError` values format
/// themselves via `LocalizedError`; anything else falls back to the system
/// description rather than a generic "Unhandled error."
///
/// can call as unnamed parameter "errorHandler(error)"
public func errorHandler(_ error: Error) -> String {
    error.localizedDescription // single expression body
}

/// An error wrapped for presentation. `Identifiable` so SwiftUI can drive an
/// alert directly from an optional of this type.
public struct PresentedError: Identifiable {
    public let id = UUID()
    public let message: String
}

/// Central sink for errors that should be shown to the user. A view observes
/// this and presents `currentError` as an alert. `report(_:)` is safe to call
/// from any thread — it hops to the main actor before mutating state — so
/// background work (e.g. the disk-writer in `MicManager`) can surface failures
/// the same way UI-thread code does.
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

// MARK: - Per-manager error types

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
