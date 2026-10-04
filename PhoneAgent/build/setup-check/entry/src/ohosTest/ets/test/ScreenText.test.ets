import { describe, expect, it } from '@ohos/hypium';
import { describeNode, isInteresting, serializeScreen, UiNode } from '../../../main/ets/agent/ScreenText';

function node(type: string, text: string, depth: number = 0): UiNode {
  return {
    depth: depth, type: type, text: text, desc: '', hint: '',
    clickable: false, editable: false, scrollable: false, checkable: false, checked: false, focused: false,
    visible: true, left: 0, top: 100, width: 100, height: 40
  };
}

export default function screenTextTest() {
  describe('ScreenText', () => {
    it('describes a tappable button with centre coordinates', 0, () => {
      const n = node('Button', 'Send');
      n.clickable = true;
      expect(describeNode(3, n)).assertEqual('[3] Button "Send" (click) @50,120');
    });

    it('shows hint and edit/focus flags for text fields', 0, () => {
      const n = node('TextArea', '');
      n.hint = 'Text message';
      n.editable = true;
      n.clickable = true;
      n.focused = true;
      expect(describeNode(0, n)).assertEqual('[0] TextArea hint="Text message" (click,edit,focused) @50,120');
    });

    it('shows switch state', 0, () => {
      const n = node('Toggle', '');
      n.checkable = true;
      n.checked = true;
      expect(describeNode(1, n)).assertContain('(checked)');
    });

    it('skips invisible, zero-size and empty non-interactive nodes', 0, () => {
      const hidden = node('Text', 'hidden');
      hidden.visible = false;
      const zero = node('Text', 'zero');
      zero.width = 0;
      const empty = node('Column', '');
      expect(isInteresting(hidden)).assertFalse();
      expect(isInteresting(zero)).assertFalse();
      expect(isInteresting(empty)).assertFalse();
      expect(isInteresting(node('Text', 'WLAN'))).assertTrue();
    });

    it('numbers only the kept nodes and maps them back to raw positions', 0, () => {
      const nodes: UiNode[] = [node('Column', ''), node('Text', 'A'), node('Column', ''), node('Text', 'B')];
      const s = serializeScreen(nodes, 10);
      expect(s.indexMap.length).assertEqual(2);
      expect(s.indexMap[0]).assertEqual(1);
      expect(s.indexMap[1]).assertEqual(3);
      expect(s.text).assertContain('[1] Text "B"');
      expect(s.truncated).assertFalse();
    });

    it('truncates long screens and says so', 0, () => {
      const nodes: UiNode[] = [];
      for (let i = 0; i < 20; i++) {
        nodes.push(node('Text', `item ${i}`));
      }
      const s = serializeScreen(nodes, 5);
      expect(s.indexMap.length).assertEqual(5);
      expect(s.truncated).assertTrue();
      expect(s.text).assertContain('truncated to 5 elements');
    });

    it('clips long texts to one line', 0, () => {
      const n = node('Text', 'line one\nline two ' + 'x'.repeat(200));
      const line = describeNode(0, n);
      expect(line.indexOf('\n')).assertEqual(-1);
      expect(line).assertContain('…');
    });

    it('folds the texts of a tappable row into the row', 0, () => {
      const row = node('Flex', '', 1);
      row.clickable = true;
      const s = serializeScreen([node('Column', '', 0), row, node('Text', 'WLAN', 2), node('Text', 'Off', 2)], 10);
      expect(s.indexMap.length).assertEqual(1);
      expect(s.indexMap[0]).assertEqual(1);
      expect(s.lines[0]).assertContain('[0] Flex "WLAN · Off" (click)');
    });

    it('keeps nested controls separate and folds only plain texts', 0, () => {
      const row = node('Flex', '', 1);
      row.clickable = true;
      const toggle = node('Toggle', '', 2);
      toggle.checkable = true;
      const s = serializeScreen([row, node('Text', 'Bluetooth', 2), toggle], 10);
      expect(s.lines.length).assertEqual(2);
      expect(s.lines[0]).assertContain('"Bluetooth"');
      expect(s.lines[1]).assertContain('Toggle (unchecked)');
    });

    it('drops a child text that repeats its button label', 0, () => {
      const button = node('Button', 'Send', 0);
      button.clickable = true;
      const s = serializeScreen([button, node('Text', 'Send', 1)], 10);
      expect(s.lines.length).assertEqual(1);
    });

    it('does not fold list items into a scrollable list', 0, () => {
      const list = node('List', '', 0);
      list.scrollable = true;
      const s = serializeScreen([list, node('Text', 'a', 1), node('Text', 'b', 1)], 10);
      expect(s.lines.length).assertEqual(3);
    });

    it('stops folding at the end of the subtree', 0, () => {
      const row = node('Flex', '', 1);
      row.clickable = true;
      const s = serializeScreen([row, node('Text', 'inside', 2), node('Text', 'outside', 1)], 10);
      expect(s.lines.length).assertEqual(2);
      expect(s.lines[0]).assertContain('"inside"');
      expect(s.lines[1]).assertContain('"outside"');
    });

    it('reports an empty screen explicitly', 0, () => {
      expect(serializeScreen([], 10).text).assertEqual('(no readable elements on screen)');
    });
  });
}
