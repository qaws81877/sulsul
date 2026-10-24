extension ModelProvider {
    /// True when the model transcribes on this Mac. Every other provider, including a custom
    /// endpoint, receives the recorded audio, so a new case is treated as remote until listed here.
    var runsOnDevice: Bool {
        switch self {
        case .whisper, .fluidAudio, .transcribeCpp, .nativeApple:
            return true
        default:
            return false
        }
    }
}
