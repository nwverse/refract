import SwiftUI

struct Parent: View {
    let model: RowsModel

    var body: some View {
        List(model.rows) { item in
            ChildRow(model: model, row: item)
        }
    }
}
