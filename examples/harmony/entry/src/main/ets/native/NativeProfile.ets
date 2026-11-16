@Component
export struct NativeProfile {
  build() {
    Column({ space: 16 }) {
      Text('Hand-written profile')
        .fontSize(24)
      Text('Only the following layout crosses the generation boundary.')
      Button('Open generated layout')
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/GeneratedProfile' });
        })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(24)
  }
}
