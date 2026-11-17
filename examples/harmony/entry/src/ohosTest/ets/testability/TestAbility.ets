import { ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import generatedSettingsTests from '../test/GeneratedSettings.test';
import generatedSettingsRenderTests from '../test/GeneratedSettingsRender.test';

export default class TestAbility extends UIAbility {
  onCreate(): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    Hypium.hypiumTest(
      abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(),
      (): void => {
        generatedSettingsTests();
        generatedSettingsRenderTests();
      }
    );
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('testability/GeneratedSettingsHost', (error): void => {
      if (error.code) {
        abilityDelegatorRegistry.getAbilityDelegator().finishTest(
          'Unable to load the generated settings native host', -1, (): void => {}
        );
      }
    });
  }
}
