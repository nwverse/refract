import { Hello } from '../generated/Hello';
import { NativeComponentScreen } from '../generated/NativeComponentScreen';

@Entry
@Component
struct GeneratedProfile {
  build() {
    Column({ space: 16 }) {
      // Native navigation calls the generated component directly, with no host.
      Hello()
      // Native navigation calls generated code, which calls native code in turn.
      NativeComponentScreen()
      Button('Back')
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
    }
    .padding(24)
    .width('100%')
    .height('100%')
  }
}
