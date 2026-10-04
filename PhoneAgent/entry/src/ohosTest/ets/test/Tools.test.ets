import { describe, expect, it } from '@ohos/hypium';
import { ContentBlock } from '../../../main/ets/agent/Anthropic';
import { parseToolCall, TOOLS } from '../../../main/ets/agent/Tools';

function call(name: string, input: Record<string, Object>): ContentBlock {
  return { type: 'tool_use', id: 'toolu_1', name: name, input: input };
}

export default function toolsTest() {
  describe('Tools.parseToolCall', () => {
    it('every tool has a strict object schema', 0, () => {
      for (const t of TOOLS) {
        expect(t.input_schema.type).assertEqual('object');
        expect(t.input_schema.additionalProperties).assertFalse();
      }
    });

    it('accepts a valid click', 0, () => {
      const r = parseToolCall(call('click', { 'index': 7 }));
      expect(r.error).assertUndefined();
      expect(r.action?.index).assertEqual(7);
    });

    it('accepts type_text, scroll, press_key, launch_app and finish', 0, () => {
      expect(parseToolCall(call('type_text', { 'index': 3, 'text': 'Będę na urodzinach' })).action?.text)
        .assertEqual('Będę na urodzinach');
      expect(parseToolCall(call('scroll', { 'index': 1, 'direction': 'up' })).action?.scrollDown).assertFalse();
      expect(parseToolCall(call('press_key', { 'key': 'home' })).action?.key).assertEqual('home');
      expect(parseToolCall(call('launch_app', { 'bundle_name': 'com.ohos.mms' })).action?.bundleName)
        .assertEqual('com.ohos.mms');
      const fin = parseToolCall(call('finish', { 'success': true, 'summary': 'Sent.' }));
      expect(fin.action?.success).assertTrue();
      expect(fin.action?.text).assertEqual('Sent.');
    });

    it('accepts set_alarm with a valid time and rejects others', 0, () => {
      const ok = parseToolCall(call('set_alarm', { 'hour': 19, 'minute': 0, 'label': 'Alarm' }));
      expect(ok.action?.hour).assertEqual(19);
      expect(ok.action?.minute).assertEqual(0);
      expect(ok.action?.text).assertEqual('Alarm');
      expect(parseToolCall(call('set_alarm', { 'hour': 7, 'minute': 30 })).action?.text).assertEqual('');
      expect(parseToolCall(call('set_alarm', { 'hour': 24, 'minute': 0 })).error).assertContain('hour');
      expect(parseToolCall(call('set_alarm', { 'hour': 19, 'minute': 60 })).error).assertContain('minute');
      expect(parseToolCall(call('set_alarm', { 'hour': '19', 'minute': 0 })).error).assertContain('hour');
    });

    it('rejects unknown tools and lists the valid ones', 0, () => {
      const r = parseToolCall(call('tap_everything', {}));
      expect(r.action).assertUndefined();
      expect(r.error).assertContain('Unknown tool');
      expect(r.error).assertContain('click');
    });

    it('rejects a missing input object', 0, () => {
      const block: ContentBlock = { type: 'tool_use', id: 'toolu_1', name: 'click' };
      expect(parseToolCall(block).error).assertContain('JSON object');
    });

    it('rejects non-integer, negative and string indexes', 0, () => {
      expect(parseToolCall(call('click', {})).error).assertContain('index');
      expect(parseToolCall(call('click', { 'index': 1.5 })).error).assertContain('integer');
      expect(parseToolCall(call('click', { 'index': -1 })).error).assertContain('out of range');
      expect(parseToolCall(call('click', { 'index': '4' })).error).assertContain('integer');
    });

    it('rejects bad enum values and wrong types', 0, () => {
      expect(parseToolCall(call('scroll', { 'index': 0, 'direction': 'left' })).error).assertContain('direction');
      expect(parseToolCall(call('press_key', { 'key': 'power' })).error).assertContain('key');
      expect(parseToolCall(call('type_text', { 'index': 0, 'text': 42 })).error).assertContain('text');
      expect(parseToolCall(call('finish', { 'success': 'yes', 'summary': 'x' })).error).assertContain('success');
    });

    it('rejects malformed bundle names and oversized text', 0, () => {
      expect(parseToolCall(call('launch_app', { 'bundle_name': 'rm -rf /' })).error).assertContain('bundle_name');
      expect(parseToolCall(call('type_text', { 'index': 0, 'text': 'a'.repeat(5000) })).error)
        .assertContain('at most');
    });
  });
}
