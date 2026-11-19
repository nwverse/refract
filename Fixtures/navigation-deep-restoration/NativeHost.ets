import { DeepNavigationModel, DeepNavigationScreen, DeepNavigationScreenDestinations, DeepRoute } from './Input';

/**
 * Source-level host contract only. The application page retains this stack and
 * integrates platform persistence; generated components do not serialize routes.
 */
@ComponentV2
export struct DeepNavigationHost {
  private stack: NavPathStack = new NavPathStack();
  @Require @Param model: DeepNavigationModel;

  build() {
    Navigation(this.stack) {
      DeepNavigationScreen({
        model: this.model,
        onPathNavigate: (destination: DeepRoute): void => {
          this.stack.pushPath({ name: DeepRoute[destination].toString() });
        }
      })
    }
    .navDestination(this.destination)
    .hideTitleBar(true)
  }

  @Builder
  destination(name: string) {
    if (name === DeepRoute[DeepRoute.detail]) {
      DeepNavigationScreenDestinations({
        destination: DeepRoute.detail,
        model: this.model,
        onPathNavigate: (destination: DeepRoute): void => {
          this.stack.pushPath({ name: DeepRoute[destination].toString() });
        }
      })
    } else if (name === DeepRoute[DeepRoute.editor]) {
      DeepNavigationScreenDestinations({
        destination: DeepRoute.editor,
        model: this.model,
        onPathNavigate: (destination: DeepRoute): void => {
          this.stack.pushPath({ name: DeepRoute[destination].toString() });
        }
      })
    }
  }
}
