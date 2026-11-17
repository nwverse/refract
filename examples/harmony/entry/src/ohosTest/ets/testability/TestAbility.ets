import { UIAbility } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import generatedSettingsTests from '../test/GeneratedSettings.test';

export default class TestAbility extends UIAbility {
  onCreate(): void {
    Hypium.hypiumTest(
      abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(),
      (): void => {
        generatedSettingsTests();
      }
    );
  }
}
