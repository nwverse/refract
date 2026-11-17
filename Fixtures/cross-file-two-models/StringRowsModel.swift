import SwiftUI

protocol StringRowsModel: RefractModel {
    var rows: [StringRow] { get }
}

struct StringRow: Identifiable {
    let id: String
    let title: String
}
