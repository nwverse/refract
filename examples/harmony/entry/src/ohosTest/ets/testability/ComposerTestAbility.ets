import { ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import generatedComposerTests from '../test/GeneratedComposer.test';

/** Separate source-prepared host; no shared test-ability page is replaced. */
export default class ComposerTestAbility extends UIAbility {
  onCreate(): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    Hypium.hypiumTest(
      abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(),
      (): void => {
        generatedComposerTests();
      }
    );
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('testability/GeneratedComposerHost', (error): void => {
      if (error.code) {
        abilityDelegatorRegistry.getAbilityDelegator().finishTest(
          'Unable to load the generated composer native host', -1, (): void => {}
        );
      }
    });
  }
}
