import { ConfigurationConstant } from '@kit.AbilityKit';
import { SettingsModel, SettingsScreen } from '../../../main/ets/generated/SettingsScreen';

/** Test-only observation belongs to the native host, not to a runtime adapter. */
@ObservedV2
class RenderSettingsModel implements SettingsModel {
  @Trace title: string = 'Example user';
  @Trace saveCount: number = 0;

  save(): void {
    this.saveCount += 1;
  }

  updateTitle(value: string): void {
    this.title = value;
  }
}

/**
 * A small native ArkUI host for the unchanged generated settings component.
 * The application theme is set by TestAbility; the host owns no renderer,
 * registry, performance instrumentation or replacement implementation.
 */
@Entry
@ComponentV2
export struct GeneratedSettingsHost {
  @Local private model: RenderSettingsModel = new RenderSettingsModel();
  @Local private notificationsEnabled: boolean = false;

  build() {
    Column() {
      Text(`Native saves: ${this.model.saveCount}`)
        .id('native_model_save_count')
      Button('Update native model')
        .id('native_model_update')
        .onClick((): void => {
          this.model.updateTitle('Updated from the native model');
        })
      Button('Use dark theme')
        .id('native_dark_theme')
        .onClick((): void => {
          this.getUIContext().getHostContext()?.getApplicationContext().setColorMode(
            ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          );
        })
      Button('Use light theme')
        .id('native_light_theme')
        .onClick((): void => {
          this.getUIContext().getHostContext()?.getApplicationContext().setColorMode(
            ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          );
        })
      SettingsScreen({
        model: this.model,
        notificationsEnabled: this.notificationsEnabled,
        onNotificationsEnabledChange: (value: boolean): void => {
          this.notificationsEnabled = value;
        }
      })
    }
    .width('100%')
    .height('100%')
  }
}
