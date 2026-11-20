import SwiftUI
import UIKit
import Observation
import os

private let imeLog = Logger(subsystem: "com.example.refract.imeverification", category: "observation")

/// The test model records the canonical host's callback order without
/// synthesizing a candidate or altering the native composition.
@Observable
final class IMEComposerModel: @MainActor ComposerModel {
    var committedDrafts: [String] = []
    var commitCount = 0
    var draftWasCommittedBeforeCommit = false

    func commitDraft(_ value: String) {
        committedDrafts.append(value)
    }

    func commit() {
        draftWasCommittedBeforeCommit = committedDrafts.last == "你" && commitCount == 0
        commitCount += 1
    }
}

struct IMEComposerHost: View {
    @State private var observer = IMETextInputObserver.shared
    @State private var draft = ""
    @State private var focusRequest = 0
    @State private var showsComposer = true
    @State private var alternateDraft = ""
    @FocusState private var alternateFocused: Bool
    @State private var model = IMEComposerModel()

    var body: some View {
        VStack(spacing: 16) {
            Text(draft.isEmpty ? "Draft: <empty>" : "Draft: \(draft)")
                .accessibilityIdentifier("draft")
                .lineLimit(2)
            if showsComposer {
                ComposerScreen(draft: $draft, focusRequest: $focusRequest, model: model)
                    .accessibilityIdentifier("composer")
            }
            Button("Restore focus") {
                alternateFocused = false
                focusRequest += 1
            }
            .accessibilityIdentifier("restore-focus")
            TextField("Alternate", text: $alternateDraft)
                .focused($alternateFocused)
                .accessibilityIdentifier("alternate-focus")
            Button(showsComposer ? "Hide host" : "Show host") {
                showsComposer.toggle()
            }
            .accessibilityIdentifier("toggle-host")
            Text("Committed drafts: \(model.committedDrafts.count)")
                .accessibilityIdentifier("committed-drafts")
            Text("Commit actions: \(model.commitCount)")
                .accessibilityIdentifier("commit-actions")
            Text("Last committed draft: \(model.committedDrafts.last ?? "<none>")")
                .accessibilityIdentifier("last-committed-draft")
            Text("Draft committed before action: \(model.draftWasCommittedBeforeCommit)")
                .accessibilityIdentifier("commit-order")
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .task { observer.installIfNeeded() }
    }
}

@main
struct RefractIMEVerificationApp: App {
    var body: some Scene {
        WindowGroup {
            IMEComposerHost()
        }
    }
}

/// Read-only observation of the real SwiftUI text input. The test never sets
/// marked text, replaces editor contents or supplies a Chinese candidate.
final class IMETextInputObserver: NSObject, UITextFieldDelegate {
    static let shared = IMETextInputObserver()
    private weak var observedField: UITextField?
    private weak var alternateField: UITextField?

    private var observedComposer: UITextField? {
        if let observedField, observedField.returnKeyType == .done { return observedField }
        if alternateField?.returnKeyType == .done { return alternateField }
        return observedField
    }

    private override init() {
        super.init()
        imeLog.info("REFRACT_IME_PROBE observer initialized")
    }

    func installIfNeeded() {
        imeLog.info("REFRACT_IME_PROBE observer installed")
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textInputDidBegin(_:)),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: UITextField.textDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: UITextView.textDidChangeNotification,
            object: nil
        )
    }

    @objc private func textInputDidBegin(_ notification: Notification) {
        guard let field = notification.object as? UITextField else { return }
        if observedField == nil {
            observedField = field
            field.delegate = self
            report()
        } else if field !== observedField {
            alternateField = field
        }
    }

    @objc private func textDidChange(_ notification: Notification) {
        if let field = notification.object as? UITextField {
            if observedField == nil {
                observedField = field
                field.delegate = self
            } else if field !== observedField {
                alternateField = field
            }
        }
        report()
    }

    func report() {
        let field = observedComposer
        let range = field?.markedTextRange
        let markedText = range.flatMap { field?.text(in: $0) } ?? ""
        let dictionary: [String: Any] = [
            "hasMarkedText": range != nil,
            "markedTextLength": markedText.count,
            "markedTextIsASCII": markedText.allSatisfy(\.isASCII),
            "fieldTextLength": field?.text?.count ?? 0,
            "fieldIsFirstResponder": field?.isFirstResponder ?? false,
            "fieldClass": field.map { String(describing: type(of: $0)) } ?? "none",
            "returnKey": field?.returnKeyType.rawValue ?? -1,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let text = String(data: data, encoding: .utf8)
        else { return }
        imeLog.info("REFRACT_IME_PROBE \(text, privacy: .public)")
        print("REFRACT_IME_PROBE \(text)")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        NSLog("REFRACT_IME_PROBE_RETURN")
        report()
        return true
    }
}

/// A zero-effect test-host reference retains the observer for the lifetime of
/// the app; it does not add behavior to the canonical shared host.
@MainActor
private let imeTextInputObserver = IMETextInputObserver.shared
