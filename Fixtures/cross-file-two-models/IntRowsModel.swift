import SwiftUI

protocol IntRowsModel: RefractModel {
    var rows: [IntRow] { get }
}

struct IntRow: Identifiable {
    let id: Int
    let title: String
}
