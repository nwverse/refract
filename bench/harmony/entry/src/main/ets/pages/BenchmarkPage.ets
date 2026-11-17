import { BenchmarkSettingsModel } from '../native/SettingsModel';
import { ReferenceSettingsScreen } from '../native/ReferenceSettingsScreen';
import { SettingsScreen } from '../generated/SettingsScreen';

@Entry
@ComponentV2
struct BenchmarkPage {
  @Local private model: BenchmarkSettingsModel = new BenchmarkSettingsModel();
  @Local private generated: boolean = true;

  build() {
    Column() {
      Button(this.generated ? 'Reference' : 'Generated')
        .id('benchmark_variant')
        .onClick((): void => {
          this.generated = !this.generated;
        })
      if (this.generated) {
        SettingsScreen({ model: this.model })
      } else {
        ReferenceSettingsScreen({ model: this.model })
      }
    }
    .width('100%')
    .height('100%')
  }
}
