import { SettingsModel } from '../generated/SettingsScreen';

@ComponentV2
export struct HandWrittenSettingsScreen {
  @Require @Param model: SettingsModel;
  @Require @Param notificationsEnabled: boolean;
  @Event onNotificationsEnabledChange: (value: boolean) => void = (value: boolean): void => {};
  @Local private displayName: string = '';

  build() {
    Column() {
      Text($r('app.string.settings_profile'))
        .fontSize(24)
      Text(this.model.title)
      TextInput({ placeholder: $r('app.string.settings_display_name'), text: this.displayName })
        .onChange((value: string) => {
          this.displayName = value;
        })
      Text($r('app.string.settings_preferences'))
      Toggle({ type: ToggleType.Switch, isOn: this.notificationsEnabled })
        .onChange((value: boolean) => {
          this.onNotificationsEnabledChange(value);
        })
      Button($r('app.string.settings_save'))
        .onClick(() => {
          this.model.save();
        })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(24)
  }
}
