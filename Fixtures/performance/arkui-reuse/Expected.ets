// Generated from Fixtures/performance/arkui-reuse/Input.swift by Refract; do not edit.
// Hand-written expected pattern pending generator and ArkTS compiler support.

// API 18+ only. For API 12–17 omit @ReusableV2, never substitute V1 @Reusable.
@ReusableV2
@ComponentV2
export struct SettingRowView {
  @Require @Param title: string;
  @Require @Param subtitle: string;
  @Require @Param enabled: boolean;
  @Event onEnabledChange: (value: boolean) => void = (value: boolean): void => {};

  build(): void {
    Row() {
      Column() {
        Text(this.title)
        Text(this.subtitle)
      }
      Toggle({ type: ToggleType.Switch, isOn: this.enabled })
        .onChange((value: boolean): void => this.onEnabledChange(value))
    }
  }
}
