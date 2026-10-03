import { describe, expect, it } from '@ohos/hypium';
import {
  AnthropicClient,
  AnthropicError,
  findModel,
  parseApiError,
  parseMessagesResponse
} from '../../../main/ets/agent/Anthropic';

export default function anthropicTest() {
  describe('Anthropic client helpers', () => {
    it('parses API error bodies and marks retryable statuses', 0, () => {
      const auth = parseApiError(401,
        '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}');
      expect(auth.errorType).assertEqual('authentication_error');
      expect(auth.retryable).assertFalse();
      const overloaded = parseApiError(529, '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}');
      expect(overloaded.retryable).assertTrue();
      expect(parseApiError(429, '{}').retryable).assertTrue();
    });

    it('survives non-JSON error bodies', 0, () => {
      const e = parseApiError(502, '<html>Bad gateway</html>');
      expect(e.errorType).assertEqual('http_error');
      expect(e.message).assertContain('502');
      expect(e.retryable).assertTrue();
    });

    it('parses a valid response', 0, () => {
      const r = parseMessagesResponse(
        '{"id":"msg_1","model":"claude-opus-5-5","stop_reason":"tool_use","content":[' +
          '{"type":"thinking","thinking":"","signature":"sig"},' +
          '{"type":"tool_use","id":"toolu_1","name":"click","input":{"index":2}}]}');
      expect(r.stop_reason).assertEqual('tool_use');
      expect(r.content.length).assertEqual(2);
      expect(r.content[1].input?.['index'] as number).assertEqual(2);
    });

    it('rejects malformed responses with a typed error', 0, () => {
      let notJson = false;
      try {
        parseMessagesResponse('{"content": [');
      } catch (e) {
        notJson = e instanceof AnthropicError && (e as AnthropicError).errorType === 'invalid_response';
      }
      expect(notJson).assertTrue();
      let missing = false;
      try {
        parseMessagesResponse('{"id":"msg_1"}');
      } catch (e) {
        missing = e instanceof AnthropicError;
      }
      expect(missing).assertTrue();
    });

    it('builds per-model requests (effort and fallbacks only where supported)', 0, () => {
      const opus = new AnthropicClient('k', findModel('claude-opus-5-5')).buildRequest('sys', [], []);
      expect(opus.output_config?.effort).assertEqual('medium');
      expect(opus.fallbacks).assertEqual('default');
      expect(opus.tool_choice.type).assertEqual('auto');
      const haiku = new AnthropicClient('k', findModel('claude-haiku-4-5')).buildRequest('sys', [], []);
      expect(haiku.output_config).assertUndefined();
      expect(haiku.fallbacks).assertUndefined();
      expect(findModel('not-a-model').id).assertEqual('claude-opus-5-5');
    });
  });
}
