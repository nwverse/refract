import { Hello } from '../generated/Hello';

@Entry
@Component
struct GeneratedProfile {
  build() {
    Column({ space: 16 }) {
      // Native navigation calls the generated component directly, with no host.
      Hello()
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
