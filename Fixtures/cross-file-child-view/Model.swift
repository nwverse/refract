import SwiftUI

protocol RowsModel: RefractModel {
    var rows: [RowItem] { get }
    func setEnabled(_ id: Int, value: Bool)
}
