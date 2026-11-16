import SwiftUI

struct StackLayout: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .medium) {
            Text(verbatim: "Profile")
            HStack(alignment: .center, spacing: .small) {
                Text(verbatim: "Enabled")
                Spacer()
            }
            ZStack(alignment: .topLeading) {
                Text(verbatim: "Background")
                Text(verbatim: "Foreground")
            }
        }
    }
}
