import SwiftUI

public enum OTControlSize: CaseIterable {
    case large
    case medium
    case small

    public var height: CGFloat {
        switch self {
        case .large:  return 50
        case .medium: return 40
        case .small:  return 34
        }
    }

    public var hitHeight: CGFloat {
        switch self {
        case .large:  return 50
        case .medium: return 40
        case .small:  return 44
        }
    }

    public var font: Font {
        switch self {
        case .large:  return .headline
        case .medium: return .subheadline.weight(.semibold)
        case .small:  return .otButtonSmall
        }
    }

    public var horizontalPadding: CGFloat {
        switch self {
        case .large:  return OTSpace.l
        case .medium: return OTSpace.m
        case .small:  return OTSpace.s
        }
    }
}
