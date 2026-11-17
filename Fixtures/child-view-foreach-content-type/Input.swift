import SwiftUI

protocol ReusableRowsModel: RefractModel {
    var rows: [ReusableRow] { get }
}

struct ReusableRow: Identifiable {
    let id: Int
    let title: String
}

struct ReusableSettingRow: View {
    let model: ReusableRowsModel
    let row: ReusableRow

    var body: some View {
        HStack(alignment: .center) {
            Text(row.title).layoutPriority(1)
        }
        .padding(8)
    }
}

struct ReusableSettings: View {
    let model: ReusableRowsModel

    var body: some View {
        List {
            ForEach(model.rows) { row in
                ReusableSettingRow(model: model, row: row)
                    .refractNativeModifier(.contentType("setting"))
            }
        }
    }
}
