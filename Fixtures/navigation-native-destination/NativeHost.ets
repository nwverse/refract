import { EscapeScreen, EscapeScreenDestinations, EscapeRoute, EscapeDetailModel } from './Input';

@ComponentV2
export struct TypedNavigationHost {
  private stack: NavPathStack = new NavPathStack();
  @Require @Param model: EscapeDetailModel;

  build() {
    Navigation(this.stack) {
      EscapeScreen({
        model: this.model,
        onPathNavigate: (destination: EscapeRoute): void => {
          this.stack.pushPath({ name: EscapeRoute[destination].toString() });
        }
      })
    }
    .navDestination(this.destination)
    .hideTitleBar(true)
  }

  @Builder
  destination(name: string) {
    if (name === EscapeRoute[EscapeRoute.detail]) {
      EscapeScreenDestinations({ destination: EscapeRoute.detail, model: this.model })
    } else if (name === EscapeRoute[EscapeRoute.native]) {
      EscapeScreenDestinations({ destination: EscapeRoute.native, model: this.model })
    }
  }
}
