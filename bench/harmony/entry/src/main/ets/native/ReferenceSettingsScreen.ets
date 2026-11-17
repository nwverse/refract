import { BenchmarkSettingsModel } from './SettingsModel';
import { SettingRow } from '../generated/SettingsScreen';
import { AppTypography } from './AppTypography';

@ComponentV2
export struct ReferenceSettingsScreen {
  @Require @Param model: BenchmarkSettingsModel;

  build() {
    Column() {
      Text(this.model.title)
        .font(AppTypography.screenTitle)
        .padding(16)
      List() {
        LazyForEach(this.model.rows, (row: SettingRow) => {
          ListItem() {
            ReferenceSettingRow({
              id: row.id,
              title: row.title,
              subtitle: row.subtitle,
              enabled: row.enabled,
              onChange: (value: boolean): void => this.model.setEnabled(row.id, value),
            })
          }
        }, (row: SettingRow): string => String(row.id))
      }
      .id('settings_list')
    }
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
struct ReferenceSettingRow {
  @Require @Param id: number;
  @Require @Param title: string;
  @Require @Param subtitle: string;
  @Require @Param enabled: boolean;
  @Event onChange: (value: boolean) => void = (value: boolean): void => {};

  build() {
    Row() {
      Column() {
        Text(this.title)
          .font(AppTypography.rowTitle)
        Text(this.subtitle)
          .font(AppTypography.rowSubtitle)
      }
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.enabled })
        .onChange((value: boolean): void => this.onChange(value))
        .id(`setting_toggle_${this.id}`)
        .accessibilityText(this.title)
    }
    .alignItems(VerticalAlign.Center)
    .id(`setting_row_${this.id}`)
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}
