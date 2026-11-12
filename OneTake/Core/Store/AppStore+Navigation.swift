import SwiftUI

// MARK: - AppStore Navigation Extension

extension AppStore {
    var currentPath: [Route] {
        if showProfile { return profilePath }
        switch tab {
        case .auditions: return auditionsPath
        case .search:    return searchPath
        case .practice:  return practicePath
        case .profile:   return profilePath
        }
    }

    /// The one "Next" action used everywhere an audition offers to continue: opens whatever its next
    /// unfinished piece needs in the audition flow (slate, scenes, headshots).
    func continueAudition(_ id: Audition.ID) {
        syncPieces()
        guard let a = audition(id) else { return }

        // If we are already on the headshot screen, advance to the next piece after headshots
        let targetPiece: Piece?
        if currentPath.contains(.headshots(for: id)) {
            targetPiece = a.pieces.first { $0.kind != .headshot && !$0.isDone }
        } else {
            targetPiece = a.nextPiece
        }

        guard let next = targetPiece else {
            push(.preview(id))
            return
        }
        switch next.kind {
        case .slate:
            camera = .shoot(id, start: .slate)
        case .fullLength:
            camera = .shoot(id, start: .fullLength)
        case .scene:
            let idx = sceneIndex(for: next, in: id)
            camera = .shoot(id, scene: idx)
        case .headshot:
            if !currentPath.contains(.headshots(for: id)) {
                push(.headshots(for: id))
            }
        }
    }

    /// Push a route on the currently selected tab's stack (or the profile sheet stack if open).
    func push(_ route: Route) {
        if showProfile {
            if profilePath.last != route {
                profilePath.append(route)
            }
            return
        }
        func appendUnique(to path: inout [Route]) {
            if path.last != route {
                path.append(route)
            }
        }
        switch tab {
        case .auditions: appendUnique(to: &auditionsPath)
        case .search:    appendUnique(to: &searchPath)
        case .practice:  appendUnique(to: &practicePath)
        case .profile:   appendUnique(to: &profilePath)
        }
    }

    /// Goes back to `route` if it's already on the current tab's stack (so "Change a take" returns to
    /// the Takes screen you came from instead of stacking a second one); pushes it otherwise.
    func popTo(_ route: Route) {
        func trim(_ path: inout [Route]) -> Bool {
            let exact = path.lastIndex(of: route)
            let match = exact ?? path.lastIndex { existing in
                switch (existing, route) {
                case let (.takes(existingID, _), .takes(targetID, _)):
                    return existingID == targetID
                case let (.preview(existingID), .preview(targetID)):
                    return existingID == targetID
                case let (.tapeCheck(existingID), .tapeCheck(targetID)):
                    return existingID == targetID
                case let (.package(existingID), .package(targetID)):
                    return existingID == targetID
                case let (.auditionDetail(existingID), .auditionDetail(targetID)):
                    return existingID == targetID
                case let (.headshots(existingID), .headshots(targetID)):
                    return existingID == targetID
                default:
                    return false
                }
            }
            guard let i = match else { return false }
            path.removeSubrange(path.index(after: i)...)
            return true
        }
        if showProfile {
            if !trim(&profilePath) { profilePath.append(route) }
            return
        }
        let found: Bool
        switch tab {
        case .auditions: found = trim(&auditionsPath)
        case .search:    found = trim(&searchPath)
        case .practice:  found = trim(&practicePath)
        case .profile:   found = trim(&profilePath)
        }
        if !found { push(route) }
    }

    /// Pops the top route from the active navigation stack.
    func pop() {
        if showProfile {
            if !profilePath.isEmpty { profilePath.removeLast() }
            return
        }
        switch tab {
        case .auditions: if !auditionsPath.isEmpty { auditionsPath.removeLast() }
        case .search:    if !searchPath.isEmpty { searchPath.removeLast() }
        case .practice:  if !practicePath.isEmpty { practicePath.removeLast() }
        case .profile:   if !profilePath.isEmpty { profilePath.removeLast() }
        }
    }

    func popToRoot() {
        if showProfile {
            profilePath.removeAll()
            return
        }
        switch tab {
        case .auditions: auditionsPath.removeAll()
        case .search:    searchPath.removeAll()
        case .practice:  practicePath.removeAll()
        case .profile:   profilePath.removeAll()
        }
    }
}
