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
 */
@ComponentV2
export struct NativeTextInputHost {
  @Require @Param draft: string;
  @Event onDraftChange: (value: string) => void = (value: string): void => {};
  @Require @Param focusRequest: number;
  @Event onDraftCommit: (value: string) => void = (value: string): void => {};
  @Event onCommit: () => void = (): void => {};

  private controller: TextInputController = new TextInputController();
  @Local private editorDraft: string = '';
  @Local private diagnostic: string = '';
  private previewActive: boolean = false;
  private lastFocusRequest: number = 0;

  aboutToAppear(): void {
    this.editorDraft = this.draft;
    this.lastFocusRequest = this.focusRequest;
  }

  @Monitor('draft')
  applyExternalDraft(): void {
    // A parent re-render or edit must not replace live native preview text.
    if (!this.previewActive) {
      this.editorDraft = this.draft;
    }
  }

  @Monitor('focusRequest')
  requestNativeFocus(): void {
    if (this.focusRequest <= this.lastFocusRequest) {
      this.diagnostic = 'NativeTextInputHost: focusRequest must increase; request a new token.';
      return;
    }
    this.lastFocusRequest = this.focusRequest;
    try {
      this.getUIContext().getFocusController().requestFocus('refract_native_text_input');
      // A focus request alone is not evidence of a visible software keyboard.
      inputMethod.getController().showTextInput((error: BusinessError): void => {
        if (error) {
          this.diagnostic = `NativeTextInputHost: native keyboard request failed (${error.code}). Request a new focus token.`;
          console.error(this.diagnostic);
        }
      });
    } catch (error) {
      const failure = error as BusinessError;
      this.diagnostic = `NativeTextInputHost: native focus request failed (${failure.code}). Request a new focus token.`;
      console.error(this.diagnostic);
    }
  }

  private nativeEditChanged(value: string, previewText?: PreviewText): void {
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
    if (this.previewActive) {
      // The public controller can clear preview text, but exposes no operation
      // that commits the IME's selected candidate. Never approximate either.
      this.diagnostic = 'NativeTextInputHost: select an IME candidate before Done; uncommitted preview text was not submitted.';
      event.keepEditableState();
      return;
    }

    this.controller.stopEditing();
    const committed: string = event.text;
    this.editorDraft = committed;
    this.onDraftCommit(committed);
    // Callers may inspect the last publication while handling onDraftCommit.
    this.onDraftChange(committed);
    this.getUIContext().getFocusController().clearFocus();
    this.onCommit();
  }

  build(): void {
    Column({ space: 8 }) {
      TextInput({ text: this.editorDraft, controller: this.controller })
        .id('refract_native_text_input')
        .enterKeyType(EnterKeyType.Done)
        .enablePreviewText(true)
        .onChange((value: string, previewText?: PreviewText): void => {
          this.nativeEditChanged(value, previewText);
        })
        .onSubmit((_enterKey: EnterKeyType, event: SubmitEvent): void => {
          this.finishNativeSubmit(event);
        })
      if (this.diagnostic.length > 0) {
        Text(this.diagnostic)
          .id('native_text_input_diagnostic')
          .fontColor(Color.Red)
      }
    }
  }
}
