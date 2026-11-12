import SwiftUI

public enum OTSurface: String, CaseIterable, Sendable {
    case standard
    case camera
}

private struct OTSurfaceKey: EnvironmentKey {
    static let defaultValue: OTSurface = .standard
}

public extension EnvironmentValues {
    var otSurface: OTSurface {
        get { self[OTSurfaceKey.self] }
        set { self[OTSurfaceKey.self] = newValue }
    }
}

public extension View {
    func otSurface(_ surface: OTSurface) -> some View {
        environment(\.otSurface, surface)
    }
}
