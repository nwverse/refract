import { SettingRow, SettingsModel } from '../generated/SettingsScreen';
export class BenchmarkRows extends BasicDataSource<SettingRow> {
  private rows: SettingRow[];

  constructor(rows: SettingRow[]) {
    super();
    this.rows = rows;
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): SettingRow {
    return this.rows[index];
  }

  replaceRow(id: number, enabled: boolean): void {
    const index = this.rows.findIndex((row: SettingRow): boolean => row.id === id);
    if (index < 0 || this.rows[index].enabled === enabled) {
      return;
    }
    const previous = this.rows[index];
    this.rows[index] = new SettingRow(id, previous.title, previous.subtitle, enabled);
    this.notifyDataChange(index);
  }
}

@ObservedV2
export class BenchmarkSettingsModel implements SettingsModel {
  @Trace title: string = 'Native settings';
  rows: BenchmarkRows;

  constructor() {
    const rows: SettingRow[] = [];
    for (let id = 0; id < 200; id++) {
      rows.push(new SettingRow(id, `Setting ${id}`, `Native setting row ${id}`, id % 2 === 0));
    }
    this.rows = new BenchmarkRows(rows);
  }

  setEnabled(id: number, value: boolean): void {
    this.rows.replaceRow(id, value);
  }
}
