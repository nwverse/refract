import SwiftUI

struct ChildRow: View {
    let model: RowsModel
    let row: RowItem

    var body: some View {
        Text(row.title)
    }
}
