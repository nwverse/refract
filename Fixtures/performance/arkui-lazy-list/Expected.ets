// Generated from Fixtures/performance/arkui-lazy-list/Input.swift by Refract; do not edit.
// Hand-written expected pattern pending generator and ArkTS compiler support.

export interface SettingItem {
  id: number;
  title: string;
  enabled: boolean;
}

@ComponentV2
export struct SettingsList {
  @Require @Param items: Array<SettingItem>;
  private dataSource: SettingsDataSource = new SettingsDataSource();

  aboutToAppear(): void {
    this.dataSource.setItems(this.items);
  }

  @Monitor('items')
  private onItemsChanged(): void {
    this.dataSource.setItems(this.items);
  }

  build(): void {
    List() {
      LazyForEach(this.dataSource, (item: SettingItem): void => {
        ListItem() {
          Row() {
            Text(item.title)
            Text(item.enabled ? 'Enabled' : 'Disabled')
          }
        }
      }, (item: SettingItem): string => item.id.toString())
    }
  }
}

class SettingsDataSource implements IDataSource {
  private items: Array<SettingItem> = [];
  private listeners: Array<DataChangeListener> = [];

  setItems(items: Array<SettingItem>): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): SettingItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}
