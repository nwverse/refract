import { BusinessError } from '@kit.BasicServicesKit';
import { inputMethod } from '@kit.IMEKit';

/**
 * Application-owned native editor for the bounded committed-draft ABI.
 *
 * PreviewText belongs to TextInput and its IME. It is never copied into a
 * separate composition value or published through the application binding.
 * API 12+ onChange supplies PreviewText; API 18+ supplies OnSubmitCallback.
 * The selected API 26 SDK must compile this file before native use.
 *
 * Public API references:
 * https://gitee.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-basic-components-textinput.md
 * https://gitee.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-text-common.md
 * https://gitee.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkui/arkui-ts/ts-custom-component-api.md
 */
@ComponentV2
export struct NativeTextInputHost {
  @Require @Param draft: string;
  @Event onDraftChange: (value: string) => void = (value: string): void => {};
  @Require @Param focusRequest: number;
  @Event onDraftCommit: (value: string) => void = (value: string): void => {};
  @Event onCommit: () => void = (): void => {};

  private controller: TextInputController = new TextInputController();
  @Local private focusId: string = '';
  @Local private editorDraft: string = '';
  @Local private diagnostic: string = '';
  private mounted: boolean = false;
  private editingEpoch: number = -1;
  private editing: boolean = false;
  private previewActive: boolean = false;
  private completingSubmit: boolean = false;
  private pendingKeyboardFailure: boolean = false;
  private lastFocusRequest: number = 0;

  aboutToAppear(): void {
    const uniqueId: number = this.getUniqueId();
    this.focusId = uniqueId >= 0 ? `refract_native_text_input_${uniqueId}` : '';
    this.diagnostic = uniqueId >= 0 ? '' : 'NativeTextInputHost: native component identity is unavailable; focus and editing are disabled.';
    this.mounted = uniqueId >= 0;
    this.editingEpoch = -1;
    this.editing = false;
    this.previewActive = false;
    this.completingSubmit = false;
    this.pendingKeyboardFailure = false;
    this.editorDraft = this.draft;
    this.lastFocusRequest = this.focusRequest;
  }

  private invalidateNativeSession(message: string): void {
    this.mounted = false;
    this.editingEpoch = -1;
    this.editing = false;
    this.previewActive = false;
    this.completingSubmit = false;
    this.diagnostic = message;
  }

  aboutToDisappear(): void {
    this.invalidateNativeSession('NativeTextInputHost: the editor disappeared; its pending preview was not submitted.');
  }

  private nativeEditingChanged(isEditing: boolean, epoch: number): void {
    if (!this.mounted || epoch !== this.editingEpoch) {
      this.diagnostic = 'NativeTextInputHost: ignored a native editing callback from an invalidated session.';
      return;
    }
    this.editing = isEditing;
    this.previewActive = false;
    if (this.completingSubmit) {
      this.diagnostic = '';
    } else if (!isEditing) {
      this.editingEpoch = -1;
      this.diagnostic = 'NativeTextInputHost: native editing ended; uncommitted preview was discarded, not published.';
    }
  }

  @Monitor('draft')
  applyExternalDraft(): void {
    if (!this.mounted) {
      return;
    }
    this.editorDraft = this.draft;
    if (this.previewActive) {
      // Keep the newer parent value. Do not cancel, retain or synthesize the
      // native candidate, and do not let a delayed callback overwrite it.
      this.editingEpoch = -1;
      this.editing = false;
      this.previewActive = false;
      this.completingSubmit = false;
      this.diagnostic = 'NativeTextInputHost: the parent draft changed during preview; editing ended and the uncommitted preview was not submitted.';
      this.controller.stopEditing();
      this.getUIContext().getFocusController().clearFocus();
    }
  }

  @Monitor('focusRequest')
  requestNativeFocus(): void {
    if (!this.mounted) {
      return;
    }
    if (this.focusRequest <= this.lastFocusRequest) {
      this.diagnostic = 'NativeTextInputHost: focusRequest must increase; request a new token.';
      return;
    }
    this.lastFocusRequest = this.focusRequest;
    const requestEpoch: number = this.focusRequest;
    this.editingEpoch = requestEpoch;
    this.editing = false;
    this.previewActive = false;
    this.diagnostic = this.pendingKeyboardFailure
      ? 'NativeTextInputHost: an earlier keyboard request failed; requesting native input again.'
      : '';
    this.pendingKeyboardFailure = false;
    try {
      this.getUIContext().getFocusController().requestFocus(this.focusId);
      // A focus request alone is not evidence of a visible software keyboard.
      inputMethod.getController().showTextInput((error: BusinessError): void => {
        if (error && this.mounted && requestEpoch === this.editingEpoch) {
          this.diagnostic = `NativeTextInputHost: native keyboard request failed (${error.code}). Request a new focus token.`;
          console.error(this.diagnostic);
        } else if (error) {
          this.pendingKeyboardFailure = true;
          console.error('NativeTextInputHost: a keyboard request failed after the editor disappeared.');
        }
      });
    } catch (error) {
      const failure = error as BusinessError;
      this.diagnostic = `NativeTextInputHost: native focus request failed (${failure.code}). Request a new focus token.`;
      console.error(this.diagnostic);
    }
  }

  private nativeEditChanged(value: string, previewText?: PreviewText): void {
    if (!this.mounted || !this.editing) {
      this.diagnostic = 'NativeTextInputHost: ignored a stale native edit outside an active editing session.';
      return;
    }
    this.previewActive = previewText !== undefined && previewText.value.length > 0;
    if (this.previewActive) {
      return;
    }
    // An empty or absent PreviewText denotes committed native editor content.
    // Candidate conversion remains entirely inside the real input method.
    this.editorDraft = value;
    this.diagnostic = '';
    this.onDraftChange(value);
  }

  private finishNativeSubmit(event: SubmitEvent): void {
    if (!this.mounted || !this.editing || this.previewActive) {
      this.diagnostic = 'NativeTextInputHost: select a candidate in an active native editing session before Done; stale or uncommitted preview was not submitted.';
      event.keepEditableState();
      return;
    }

    this.editing = false;
    this.previewActive = false;
    this.completingSubmit = true;
    this.controller.stopEditing();
    const committed: string = event.text;
    this.editorDraft = committed;
    this.diagnostic = '';
    this.onDraftCommit(committed);
    // Callers may inspect the last publication while handling onDraftCommit.
    this.onDraftChange(committed);
    this.getUIContext().getFocusController().clearFocus();
    this.onCommit();
    this.completingSubmit = false;
    this.editingEpoch = -1;
  }

  build(): void {
    Column({ space: 8 }) {
      TextInput({ text: this.editorDraft, controller: this.controller })
        .id(this.focusId)
        .enterKeyType(EnterKeyType.Done)
        .enablePreviewText(true)
        .onEditChange((isEditing: boolean): void => {
          this.nativeEditingChanged(isEditing, this.editingEpoch);
        })
        .onChange((value: string, previewText?: PreviewText): void => {
          this.nativeEditChanged(value, previewText);
        })
        .onSubmit((_enterKey: EnterKeyType, event: SubmitEvent): void => {
          this.finishNativeSubmit(event);
        })
      if (this.diagnostic.length > 0) {
        Text(this.diagnostic)
          .fontColor(Color.Red)
      }
    }
  }
}
