import SwiftUI
import SwiftUI

struct ChatBlock: Identifiable {
    let id: String
    let text: String
}

struct ChatMessage: Identifiable {
    let id: String
    let revision: UInt64
    let blocks: [ChatBlock]
    let finalized: Bool
}
