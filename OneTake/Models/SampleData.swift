import Foundation

/// What's left of the old mock dataset: `findings` backs the Automated Tape Check screen, which is
/// advisory copy, not a real computer-vision framing/audio analysis of the take (that's a genuinely
/// separate, much larger feature — see the project notes). Everything else that used to live here —
/// sample auditions, takes, practice pieces — is gone: real data now comes from what the actor
/// actually adds, records and practices, persisted by `AppStore`/`Persistence`.
enum SampleData {
    static let findings: [TapeFinding] = [
        .init(category: "Eyeline", title: "You looked into the lens", where_: "0:41 · 4 s", advice: "Casting wants your eyes just beside the lens, on the reader."),
        .init(category: "Reader volume", title: "Your reader track is louder than you", where_: "0:18 · +3 dB", advice: "Lower it so casting hears you first.")
    ]
}
