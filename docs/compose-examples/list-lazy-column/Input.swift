import SwiftUI

struct Contact: Identifiable {
    let id: String
    let name: String
}

struct ContactListView: View {
    var contacts: [Contact]

    var body: some View {
        List(contacts) { contact in
            Text(contact.name)
        }
    }
}
