import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// True if an image asset exists in the bundle (so views can fall back to palette
/// placeholders before the art is added).
enum Art {
    static func exists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }
}
