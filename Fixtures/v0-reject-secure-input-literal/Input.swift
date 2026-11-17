import SwiftUI

struct HardcodedSecret: View {
    var body: some View {
        SecureField("settings.password", text: "hunter2")
    }
}
