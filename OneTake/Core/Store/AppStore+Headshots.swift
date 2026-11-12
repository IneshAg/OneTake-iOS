import Foundation

// MARK: - AppStore Headshots Extension

extension AppStore {
    /// Audition headshots are independent from the profile default headshot. Each audition's headshot
    /// piece is marked done only if that specific audition has a headshot attached.
    func syncHeadshotPieces() {
        syncPieces()
    }

    /// Notifies views observing headshotVersion to refresh disk headshots.
    func bumpHeadshotVersion() {
        headshotVersion += 1
    }
}
