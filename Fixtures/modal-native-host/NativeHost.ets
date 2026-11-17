import { ModalHostScreen } from './Input';

/**
 * Application-owned ArkUI alert host. This source is an integration contract,
 * not verified ArkTS compilation: no HarmonyOS compiler is installed locally.
 * There is no modal registry, overlay controller or Refract runtime.
 */
@ComponentV2
export struct NativeModalHost {
  @Require @Param model: ProfileModel;
  @Local private showDeleteConfirmation: boolean = false;

  build() {
    ModalHostScreen({
      model: this.model,
      showDeleteConfirmation: this.showDeleteConfirmation,
      onShowDeleteConfirmationChange: (visible: boolean): void => {
        this.showDeleteConfirmation = visible;
      },
      onShowDeleteConfirmationPresent: (): void => {
        this.getUIContext().showAlertDialog({
          title: $r('app.string.modal_delete_title'),
          message: $r('app.string.modal_delete_message'),
          autoCancel: true,
          primaryButton: {
            value: $r('app.string.modal_delete_confirm'),
            action: (): void => {
              this.showDeleteConfirmation = false;
              this.model.confirmDelete();
            }
          },
          secondaryButton: {
            value: $r('app.string.modal_delete_cancel'),
            action: (): void => {
              this.showDeleteConfirmation = false;
            }
          },
          onWillDismiss: (action: DismissDialogAction): void => {
            action.dismiss();
            this.showDeleteConfirmation = false;
          }
        });
      }
    })
  }
}
