import { NativeProfile } from '../native/NativeProfile';

@Entry
@Component
struct Index {
  build() {
    Column() {
      NativeProfile()
    }
    .width('100%')
    .height('100%')
  }
}
