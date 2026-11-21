import { Component, Driver, ON } from '@kit.TestKit';
import { KeyCode } from '@kit.InputKit';
import { describe, expect, it } from '@ohos/hypium';

async function idle(driver: Driver): Promise<void> {
  expect(await driver.waitForIdle(500, 5000)).assertTrue();
}

async function component(driver: Driver, id: string): Promise<Component> {
  await driver.assertComponentExist(ON.id(id));
  const found: Component | null = await driver.findComponent(ON.id(id));
  expect(found !== null).assertTrue();
  return found as Component;
}

async function click(driver: Driver, id: string): Promise<void> {
  await (await component(driver, id)).click();
  await idle(driver);
}

async function text(driver: Driver, id: string): Promise<string> {
  return await (await component(driver, id)).getText();
}

async function draftCount(driver: Driver): Promise<number> {
  const value: string = await text(driver, 'native_draft_count');
  return Number(value.substring('Native draft events: '.length));
}

async function editors(driver: Driver): Promise<Component[]> {
  const found: Component[] = await driver.findComponents(ON.type('TextInput'));
  expect(found.length).assertEqual(2);
  expect(await found[0].getId() !== await found[1].getId()).assertTrue();
  return found;
}

async function assertOnlyFocused(editor: Component, other: Component): Promise<void> {
  expect(await editor.isFocused()).assertTrue();
  expect(await other.isFocused()).assertFalse();
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
      let inputs: Component[] = await editors(driver);
      const firstId: string = await inputs[0].getId();
      const secondId: string = await inputs[1].getId();
      const scroll: Component = await component(driver, 'native_composer_scroll');
      await scroll.scrollSearch(ON.id(secondId));
      await idle(driver);
      inputs = await editors(driver);
      expect(await text(driver, 'native_parent_draft')).assertEqual('Retained draft');

      await click(driver, 'native_second_focus_request');
      await assertOnlyFocused(inputs[1], inputs[0]);
      await click(driver, 'native_focus_request');
      await assertOnlyFocused(inputs[0], inputs[1]);
      await inputs[0].inputText('Native committed edit');
      await idle(driver);
      expect(await text(driver, 'native_parent_draft')).assertEqual('Native committed edit');

      await click(driver, 'native_other_focus');
      expect(await (await component(driver, 'native_other_focus')).isFocused()).assertTrue();
      await assertOnlyFocused(inputs[1], inputs[0]);
      await click(driver, 'native_external_draft');
      expect(await text(driver, 'native_parent_draft')).assertEqual('External committed edit');
      await click(driver, 'native_remove_composer');
      inputs = await editors(driver);
      expect(await inputs[0].getId() !== firstId).assertTrue();
      expect(await inputs[0].getId() === secondId).assertTrue();
      await click(driver, 'native_restore_composer');
      inputs = await editors(driver);
      expect(await text(driver, 'native_parent_draft')).assertEqual('External committed edit');
      await inputs[0].inputText('Native committed edit');
      await idle(driver);
      expect(await text(driver, 'native_parent_draft')).assertEqual('Native committed edit');

      await click(driver, 'native_focus_request');
      await assertOnlyFocused(inputs[0], inputs[1]);
      const beforeEnter: number = await draftCount(driver);
      await driver.triggerKey(KeyCode.KEYCODE_ENTER);
      await idle(driver);
      expect(await text(driver, 'native_submitted_draft')).assertEqual('Native committed edit');
      expect(await draftCount(driver)).assertEqual(beforeEnter + 1);
      expect(await text(driver, 'native_commit_events')).assertEqual('Native events: draft:Native committed edit,commit');
      expect(await text(driver, 'native_parent_draft')).assertEqual('Native committed edit');
      expect(await inputs[0].isFocused()).assertFalse();
      done();
    });
  });
}
