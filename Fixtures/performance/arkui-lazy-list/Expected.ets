// Generated from Fixtures/performance/arkui-lazy-list/Input.swift by Refract; do not edit.
// Hand-written expected pattern pending generator and ArkTS compiler support.

@ObservedV2
export class SettingItem {
  @Trace id: number;
  @Trace title: string;
  @Trace enabled: boolean;

  constructor(id: number, title: string, enabled: boolean) {
    this.id = id;
    this.title = title;
    this.enabled = enabled;
  }
}

export interface SettingsListModel {
  items: BasicDataSource<SettingItem>;
}

@ComponentV2
export struct SettingsList {
  @Require @Param model: SettingsListModel;

  build() {
    List() {
      LazyForEach(this.model.items, (item: SettingItem) => {
        ListItem() {
          Row() {
            Text(item.title)
            Text(item.enabled ? 'Enabled' : 'Disabled')
          }
        }
      }, (item: SettingItem): string => String(item.id))
    }
  }
}
