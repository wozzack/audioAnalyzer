/* 
 these descriptions suck ass rn, not specific enough nor gives enough context.
 redo the categorization of the groupings later. should have error report both 
 offendingvfunction and the actual type of error somehow.
 */

import SwiftUI
import AudioKit
import Foundation

public enum AudioManagerError: Error {
    case GenericFailure
    // for when unwrapping audio object
    case AudioObjectInitializationFailure
    
    case StartEngineFailure
    case AddPlaylistFailure
    case ConvertToURLFailure
    case ConvertToAudioObjectFailure
    case LoadAudioFailure
    case PlaybackFailure
    case LoopingFailure
    case DeleteFromPlaylistError
    case GetProgressFailure
    case TimeSeekingFailure
    
    func errorLogging() -> String {
        switch self {
        case .GenericFailure:
            return "Some type of failure."
        case .AudioObjectInitializationFailure:
            return "Failure to initialize AudioObject."
            
        case .StartEngineFailure:
            return "Failure to start engine."
        case .AddPlaylistFailure:
            return "Failure to add AudioObject to playlist."
        case .ConvertToURLFailure:
            return "Failure to convert string into URL-type."
        case .ConvertToAudioObjectFailure:
            return "Failure to convert intoAudioObject-type."
        case .LoadAudioFailure:
            return "Failure to load audio into player."
        case .PlaybackFailure:
            return "Failure to playback audio."
        case .LoopingFailure:
            return "Failure to loop audio."
        case .DeleteFromPlaylistError:
            return "Failure to delete AudioObject from playlist."
        case .GetProgressFailure:
            return "Failure to get progress of current audio file playback."
        case .TimeSeekingFailure:
            return "Failure to setup seeking parameters for audio playback."
        }
    }
}
