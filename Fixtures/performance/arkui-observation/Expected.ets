// Generated from Fixtures/performance/arkui-observation/Input.swift by Refract; do not edit.
// Hand-written expected pattern pending generator and ArkTS compiler support.

export interface CounterModel {
  title: string;
  count: number;
  increment(): void;
}

@ComponentV2
export struct CounterView {
  @Require @Param model: CounterModel;

  build(): void {
    Column() {
      Text(this.model.title)
      Text(`Count: ${this.model.count}`)
      Button('Increment')
        .onClick((): void => this.model.increment())
    }
  }
}
