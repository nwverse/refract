import { NavigationScreen, NavigationScreenDestinations, Route, DetailModel } from './Input';

@ComponentV2
export struct TypedNavigationHost {
  private stack: NavPathStack = new NavPathStack();
  @Require @Param model: DetailModel;

  build() {
    Navigation(this.stack) {
      NavigationScreen({
        model: this.model,
        onPathNavigate: (destination: Route): void => {
          this.stack.pushPath({ name: Route[destination].toString() });
        }
      })
    }
    .navDestination(this.destination)
    .hideTitleBar(true)
  }

  @Builder
  destination(name: string) {
    if (name === Route[Route.detail]) {
      NavigationScreenDestinations({ destination: Route.detail, model: this.model })
    } else if (name === Route[Route.native]) {
      NavigationScreenDestinations({ destination: Route.native, model: this.model })
    }
  }
}
