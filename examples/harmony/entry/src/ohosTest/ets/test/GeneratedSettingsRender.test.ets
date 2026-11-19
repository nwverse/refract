import { Component, Driver, ON, On } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';

const CACHE: string = '/data/storage/el2/base/cache';

async function idle(driver: Driver): Promise<void> {
  expect(await driver.waitForIdle(500, 5000)).assertTrue();
}

async function capture(driver: Driver, name: string): Promise<void> {
  expect(await driver.screenCap(`${CACHE}/${name}.png`)).assertTrue();
  // This requires the selected API 26 SDK. An unsupported or failed dump is
  // a rendering-verification blocker, not a case to skip or replace with text.
  expect(await driver.dumpLayout(`${CACHE}/${name}-layout.json`)).assertTrue();
}

async function checked(driver: Driver, value: boolean): Promise<Component> {
  const matcher: On = ON.type('Toggle').checkable(true).checked(value);
  await driver.assertComponentExist(matcher);
  const toggle: Component | null = await driver.findComponent(matcher);
  expect(toggle !== null).assertTrue();
  return toggle as Component;
}

async function saveCount(driver: Driver): Promise<number> {
  const model = await driver.findComponent(ON.id('native_model_save_count'));
  expect(model !== null).assertTrue();
  const text: string = await (model as Component).getText();
  expect(text.startsWith('Native saves: ')).assertTrue();
  return Number(text.substring('Native saves: '.length));
}

/**
 * Native Hypium/UI Test execution of the real generated screen. This is source-
 * prepared only until the authorized compiler and an owned target execute it.
 * These checks report rendering and accessibility-node behavior, never speed.
 */
export default function generatedSettingsRenderTests(): void {
  describe('GeneratedSettingsRender', (): void => {
    it('native_controls_binding_model_list_and_captures', 0, async (done: Function) => {
      const driver: Driver = Driver.create();
      await idle(driver);
      for (const label of ['Profile', 'Example user', 'Preferences', 'Notifications', 'Save']) {
        await driver.assertComponentExist(ON.text(label));
      }
      const label: Component | null = await driver.findComponent(ON.text('Notifications'));
      expect(label !== null).assertTrue();
      expect(await (label as Component).isEnabled()).assertTrue();

      let toggle: Component = await checked(driver, false);
      expect(await toggle.getType()).assertEqual('Toggle');
      expect(await toggle.isEnabled()).assertTrue();
      expect(await toggle.isClickable()).assertTrue();
      expect(await toggle.isCheckable()).assertTrue();
      const labelBounds = await (label as Component).getBounds();
      const toggleBounds = await toggle.getBounds();
      expect(labelBounds.top < toggleBounds.bottom && labelBounds.bottom > toggleBounds.top).assertTrue();
      await capture(driver, 'generated-settings-light');

      await toggle.click();
      await idle(driver);
      toggle = await checked(driver, true);
      await toggle.click();
      await idle(driver);
      await checked(driver, false);

      await driver.assertComponentExist(ON.id('native_model_update'));
      await (await driver.findComponent(ON.id('native_model_update')) as Component).click();
      await idle(driver);
      await driver.assertComponentExist(ON.text('Updated from the native model'));
      const input: Component | null = await driver.findComponent(ON.type('TextInput'));
      expect(input !== null).assertTrue();
      await (input as Component).inputText('Native render check');
      await idle(driver);
      await driver.assertComponentExist(ON.text('Native render check'));

      const list: Component | null = await driver.findComponent(ON.type('List'));
      expect(list !== null).assertTrue();
      const save: Component = await (list as Component).scrollSearch(ON.text('Save'));
      expect(await save.isClickable()).assertTrue();
      await save.click();
      await idle(driver);
      expect(await saveCount(driver)).assertEqual(1);
      await capture(driver, 'generated-settings-light-after-scroll');
      await (list as Component).scrollToTop();
      await idle(driver);
      await driver.assertComponentExist(ON.text('Updated from the native model'));
      await driver.assertComponentExist(ON.id('native_model_save_count'));
      await capture(driver, 'generated-settings-light-after-scroll-return');
      done();
    });

    it('native_dark_theme_and_accessibility_layout', 0, async (done: Function) => {
      const driver: Driver = Driver.create();
      await idle(driver);
      await driver.assertComponentExist(ON.id('native_dark_theme'));
      await (await driver.findComponent(ON.id('native_dark_theme')) as Component).click();
      await idle(driver);
      await driver.assertComponentExist(ON.text('Example user'));
      await checked(driver, false);
      await driver.assertComponentExist(ON.id('native_model_save_count'));
      await capture(driver, 'generated-settings-dark');
      await (await driver.findComponent(ON.id('native_light_theme')) as Component).click();
      await idle(driver);
      done();
    });
  });
}
