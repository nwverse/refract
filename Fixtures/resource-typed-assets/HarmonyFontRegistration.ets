// The consuming application registers its raw font before using this component.
// This is an integration contract, not a generated runtime or an automatic initializer.
import { font } from '@kit.ArkUI';

export function registerAppBody(uiContext: UIContext): void {
  uiContext.getFont().registerFont({
    familyName: 'app_body',
    familySrc: $rawfile('app_body.ttf'),
  });
}
