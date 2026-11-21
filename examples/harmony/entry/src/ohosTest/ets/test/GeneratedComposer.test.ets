import { Component, Driver, ON } from '@kit.TestKit';
import { KeyCode } from '@kit.InputKit';
import { describe, expect, it } from '@ohos/hypium';

async function idle(driver: Driver): Promise<void> {
  expect(await driver.waitForIdle(500, 5000)).assertTrue();
}

async function click(driver: Driver, id: string): Promise<void> {
  await driver.assertComponentExist(ON.id(id));
  const component: Component | null = await driver.findComponent(ON.id(id));
  expect(component !== null).assertTrue();
  await (component as Component).click();
  await idle(driver);
}

async function text(driver: Driver, id: string): Promise<string> {
  await driver.assertComponentExist(ON.id(id));
  const component: Component | null = await driver.findComponent(ON.id(id));
  expect(component !== null).assertTrue();
  return await (component as Component).getText();
}

async function draftCount(driver: Driver): Promise<number> {
  const value: string = await text(driver, 'native_draft_count');
  return Number(value.substring('Native draft events: '.length));
}

/**
 * Source-prepared native checks for committed editing, focus, done and retention.
 * UI Test inputText is NOT an IME preedit or candidate-selection test.
 * A real Chinese IME and a human-operated candidate choice are still required.
 */
export default function generatedComposerTests(): void {
  describe('GeneratedComposer', (): void => {
    it('committed_draft_focus_done_and_recreation', 0, async (done: Function) => {
      const driver: Driver = Driver.create();
      await idle(driver);
      await driver.assertComponentExist(ON.id('refract_native_text_input'));
      const input: Component | null = await driver.findComponent(ON.id('refract_native_text_input'));
      expect(input !== null).assertTrue();
      expect(await text(driver, 'native_parent_draft')).assertEqual('Retained draft');

      await click(driver, 'native_focus_request');
      await (input as Component).inputText('Native committed edit');
      await idle(driver);
      expect(await text(driver, 'native_parent_draft')).assertEqual('Native committed edit');

      await click(driver, 'native_other_focus');
      await click(driver, 'native_external_draft');
      expect(await text(driver, 'native_parent_draft')).assertEqual('External committed edit');
      await click(driver, 'native_remove_composer');
      expect(await driver.findComponent(ON.id('refract_native_text_input')) === null).assertTrue();
      await click(driver, 'native_restore_composer');
      await driver.assertComponentExist(ON.id('refract_native_text_input'));
      expect(await text(driver, 'native_parent_draft')).assertEqual('Native committed edit');
      const recreated: Component | null = await driver.findComponent(ON.id('refract_native_text_input'));
      expect(recreated !== null).assertTrue();

      await click(driver, 'native_focus_request');
      const beforeEnter: number = await draftCount(driver);
      await driver.triggerKey(KeyCode.KEYCODE_ENTER);
      await idle(driver);
      expect(await text(driver, 'native_submitted_draft')).assertEqual('Native committed edit');
      expect(await draftCount(driver)).assertEqual(beforeEnter + 1);
      expect(await text(driver, 'native_commit_events')).assertEqual('Native events: draft:Native committed edit,commit');
      expect(await text(driver, 'native_parent_draft')).assertEqual('Native committed edit');
      done();
    });
  });
}
