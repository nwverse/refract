import { AppSettingsModel } from '../native/AppSettingsModel';
import { HandWrittenSettingsScreen } from '../native/HandWrittenSettingsScreen';
import { Hello } from '../generated/Hello';
import { NativeComponentScreen } from '../generated/NativeComponentScreen';
import { SettingsScreen } from '../generated/SettingsScreen';

@Entry
@ComponentV2
struct GeneratedProfile {
  @Local private model: AppSettingsModel = new AppSettingsModel();
  @Local private notificationsEnabled: boolean = true;
  @Local private useGeneratedSettings: boolean = true;

  build() {
    Column({ space: 16 }) {
      // Native navigation calls generated code, which calls native code in turn.
      Hello()
      NativeComponentScreen()
      Button(this.useGeneratedSettings ? 'Use hand-written settings' : 'Use generated settings')
        .onClick(() => {
          this.useGeneratedSettings = !this.useGeneratedSettings;
        })
      if (this.useGeneratedSettings) {
        SettingsScreen({
          model: this.model,
          notificationsEnabled: this.notificationsEnabled,
          onNotificationsEnabledChange: (value: boolean): void => {
            this.notificationsEnabled = value;
          }
        })
      } else {
        HandWrittenSettingsScreen({
          model: this.model,
          notificationsEnabled: this.notificationsEnabled,
          onNotificationsEnabledChange: (value: boolean): void => {
            this.notificationsEnabled = value;
          }
        })
      }
      Button('Back')
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
    }
    .padding(24)
    .width('100%')
    .height('100%')
  }
}
