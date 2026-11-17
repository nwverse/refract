import { describe, expect, it } from '@ohos/hypium';
import { SettingsModel } from '../../../main/ets/generated/SettingsScreen';

class TestSettingsModel implements SettingsModel {
  title: string = 'Native model';
  saveCount: number = 0;

  save(): void {
    this.saveCount += 1;
  }
}

/** Source-prepared contract test; no native SDK compilation has been claimed. */
export default function generatedSettingsTests(): void {
  describe('GeneratedSettings', (): void => {
    it('generated_model_interface_accepts_a_typed_native_implementation', 0, (): void => {
      const model: SettingsModel = new TestSettingsModel();
      expect(model.title).assertEqual('Native model');
      model.save();
      expect((model as TestSettingsModel).saveCount).assertEqual(1);
    });
  });
}
