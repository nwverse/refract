import { WidthSizeClass } from './Input';
import { AdaptiveSettingsModel } from './Input';

@ObservedV2
export class AdaptiveBreakpointOwner {
  @Trace widthSizeClass: WidthSizeClass = WidthSizeClass.compact;

  onBreakpointChange(breakpoint: string): void {
    this.widthSizeClass = breakpoint === 'xs' || breakpoint === 'sm' ?
      WidthSizeClass.compact : WidthSizeClass.expanded;
  }
}

// The app owns this component and its single native navigation stack. The
// generated AdaptiveSettingsScreen receives this same observed width-class input.
// Source-only contract: no HarmonyOS compiler or render target is available.
@ComponentV2
export struct AdaptiveSettingsNativeHost {
  @Require @Param owner: AdaptiveBreakpointOwner;
  @Require @Param model: AdaptiveSettingsModel;
  @Local private notificationsEnabled: boolean = false;
  @Local private displayName: string = '';

  build() {
    GridRow({
      breakpoints: {
        value: ['600vp', '840vp'],
        reference: BreakpointsReference.WindowSize
      }
    }) {
      GridCol({ span: 12 }) {
        AdaptiveSettingsScreen({
          model: this.model,
          widthSizeClass: this.owner.widthSizeClass,
          notificationsEnabled: this.notificationsEnabled,
          displayName: this.displayName,
          onDisplayNameChange: (value: string): void => {
            this.displayName = value;
          },
          onNotificationsEnabledChange: (value: boolean): void => {
            this.notificationsEnabled = value;
          }
        })
      }
    }
    .onBreakpointChange((breakpoint: string) => {
      this.owner.onBreakpointChange(breakpoint);
    })
  }
}
