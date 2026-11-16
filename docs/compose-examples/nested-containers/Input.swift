import SwiftUI

struct ProfileView: View {
    var name: String
    var bio: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name)
                .font(.title)
            HStack(spacing: 8) {
                Text("Location:")
                Text("Earth")
            }
            Text(bio)
                .foregroundColor(.secondary)
        }
    }
}
