import { describe, expect, it } from '@ohos/hypium';
import { stepText, targetFromLine } from '../../../main/ets/agent/StepText';
import { ToolAction } from '../../../main/ets/agent/Tools';

function action(name: string): ToolAction {
  return { name: name, index: -1, text: '', bundleName: '', scrollDown: true, key: '', success: true };
}

export default function stepTextTest() {
  describe('StepText', () => {
    it('targetFromLine prefers text, then desc, then hint, then the type', 0, () => {
      expect(targetFromLine('[6] TextArea "Hello" (click,edit)')).assertEqual('"Hello"');
      expect(targetFromLine('[2] Button desc="Send" (click)')).assertEqual('"Send"');
      expect(targetFromLine('[3] TextInput hint="Message" (click,edit)')).assertEqual('"Message"');
      expect(targetFromLine('[4] Image (click)')).assertEqual('image');
      expect(targetFromLine('')).assertEqual('');
    });

    it('launch_app uses the app label, falling back to the bundle name', 0, () => {
      const a = action('launch_app');
      a.bundleName = 'com.ohos.mms';
      expect(stepText(a, 'Messages', '')).assertEqual('Open Messages');
      expect(stepText(a, '', '')).assertEqual('Open com.ohos.mms');
    });

    it('click, type_text and scroll name their target', 0, () => {
      const click = action('click');
      click.index = 2;
      expect(stepText(click, '', '[2] Button "Send" (click)')).assertEqual('Tap "Send"');
      expect(stepText(click, '', '')).assertEqual('Tap item 2');
      const type = action('type_text');
      type.index = 3;
      type.text = 'Będę';
      expect(stepText(type, '', '[3] TextInput hint="Message" (edit)')).assertEqual('Type "Będę" into "Message"');
      const scroll = action('scroll');
      scroll.index = 1;
      scroll.scrollDown = false;
      expect(stepText(scroll, '', '[1] List (scroll)')).assertEqual('Scroll up');
    });

    it('read_screen, list_apps and press_key read as plain verbs', 0, () => {
      expect(stepText(action('read_screen'), '', '')).assertEqual('Look at the screen');
      expect(stepText(action('list_apps'), '', '')).assertEqual('Check the installed apps');
      const key = action('press_key');
      key.key = 'home';
      expect(stepText(key, '', '')).assertEqual('Press Home');
    });
  });
}
