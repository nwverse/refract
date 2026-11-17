import SwiftUI

struct IntRowsScreen: View {
    let model: IntRowsModel

    var body: some View {
        List(model.rows) { row in
            Text(row.title)
        }
    }
}

struct StringRowsScreen: View {
    let model: StringRowsModel

    var body: some View {
        List { ForEach(model.rows) { row in
            Text(row.title)
        } }
    }
}
