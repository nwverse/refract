import { ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import generatedSettingsRenderTests from '../test/GeneratedSettingsRender.test';
import generatedComposerTests from '../test/GeneratedComposer.test';

export default class TestAbility extends UIAbility {
  private hostPage: string = '';

  onCreate(): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    const parameters: Record<string, string> = abilityDelegatorRegistry.getArguments().parameters;
    const selectedSuite: string = parameters['refractSuite'] ?? '';
    const filteredSuite: string = parameters['class'] ?? '';
    if (selectedSuite !== 'GeneratedComposer' && selectedSuite !== 'GeneratedSettingsRender') {
      throw new Error('Unknown or missing native verification suite.');
    }
    if (filteredSuite !== selectedSuite) {
      throw new Error('Native verification suite parameters are missing or contradictory.');
    }
    Hypium.hypiumTest(
      abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(),
      (): void => {
        if (selectedSuite === 'GeneratedComposer') {
          this.hostPage = 'testability/GeneratedComposerHost';
          generatedComposerTests();
        } else if (selectedSuite === 'GeneratedSettingsRender') {
          this.hostPage = 'testability/GeneratedSettingsHost';
          generatedSettingsRenderTests();
        } else {
          throw new Error('Unsupported native verification selection; use the bounded repository runner.');
        }
      }
    );
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent(this.hostPage, (error): void => {
      if (error.code) {
        abilityDelegatorRegistry.getAbilityDelegator().finishTest(
          `Unable to load the selected generated native host: ${error.code}`, -1, (): void => {}
        );
      }
    });
  }
}
