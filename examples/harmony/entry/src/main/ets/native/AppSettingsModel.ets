import { SettingsModel } from '../generated/SettingsScreen';

@ObservedV2
export class AppSettingsModel implements SettingsModel {
  @Trace title: string;

  constructor(title: string = 'Profile settings') {
    this.title = title;
  }

  save(): void {
    // The native application owns persistence and side effects.
  }
}
