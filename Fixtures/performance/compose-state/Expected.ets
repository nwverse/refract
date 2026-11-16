// Generated from Fixtures/performance/compose-state/Input.swift by Refract; do not edit.
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

// The consuming app, not the generated screen, supplies observation.
@ObservedV2
class CounterModelImplementation implements CounterModel {
  @Trace title: string = 'Counter';
  @Trace count: number = 0;

  increment(): void {
    this.count += 1;
  }
}
