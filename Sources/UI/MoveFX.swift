import AppKit
// What a move looks like on the stage: its effect over the fighters, and how they move while it plays.

extension WalkerView {
    /// A move's effect, drawn over the fighters while `beat` plays (u = seconds into it); at = where each side stands (feet at y + 32, centre x + 16, in dots).
    func moveFX(_ fb: inout FB, _ beat: Beat, _ u: Double, _ b: Battle, _ at: [Side: (x: Int, y: Int)]) {}
    /// How the fighters move for this beat, if a move has its own way; nil = the stage's usual pose.
    func movePose(_ beat: Beat, _ u: Double, _ b: Battle) -> Pose? { nil }
}
/// Self-test checks for this file (run by selftest()).
@MainActor func moveChecks() -> [(Bool, String)] { [] }
