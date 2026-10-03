import { describe, expect, it } from '@ohos/hypium';
import { ApiMessage } from '../../../main/ets/agent/Anthropic';
import {
  buildOpenAiRequest,
  parseOpenAiError,
  parseOpenAiResponse,
  toOpenAiMessages
} from '../../../main/ets/agent/OpenAiCompat';
import { LlmError } from '../../../main/ets/agent/Http';
import { parseToolCall, TOOLS } from '../../../main/ets/agent/Tools';

function conversation(): ApiMessage[] {
  return [
    { role: 'user', content: [{ type: 'text', text: 'Task: open settings' }] },
    {
      role: 'assistant', content: [
      { type: 'text', text: 'Opening Settings.' },
      { type: 'tool_use', id: 'call_1', name: 'launch_app', input: { 'bundle_name': 'com.ohos.settings' } },
      { type: 'tool_use', id: 'call_2', name: 'click', input: { 'index': 3 } }
    ]
    },
    {
      role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'call_1', content: 'Opened.' },
      { type: 'tool_result', tool_use_id: 'call_2', content: 'Index 3 is not on the screen', is_error: true }
    ]
    },
    { role: 'user', content: [{ type: 'text', text: 'Continue.' }] }
  ];
}

export default function openAiCompatTest() {
  describe('OpenAI-compatible client (OpenAI, xAI)', () => {
    it('converts the conversation to chat messages', 0, () => {
      const msgs = toOpenAiMessages('SYSTEM', conversation());
      expect(msgs[0].role).assertEqual('system');
      expect(msgs[0].content).assertEqual('SYSTEM');
      expect(msgs[1].role).assertEqual('user');
      const assistant = msgs[2];
      expect(assistant.role).assertEqual('assistant');
      expect(assistant.content).assertEqual('Opening Settings.');
      expect(assistant.tool_calls?.length).assertEqual(2);
      expect(assistant.tool_calls?.[0].function.arguments).assertEqual('{"bundle_name":"com.ohos.settings"}');
      // tool results become role:"tool" messages right after the assistant turn
      expect(msgs[3].role).assertEqual('tool');
      expect(msgs[3].tool_call_id).assertEqual('call_1');
      expect(msgs[4].content).assertContain('ERROR: ');
      expect(msgs[5].role).assertEqual('user');
    });

    it('builds a request with function tools and auto tool choice', 0, () => {
      const req = buildOpenAiRequest('gpt-5', 'SYSTEM', TOOLS, conversation());
      expect(req.model).assertEqual('gpt-5');
      expect(req.tool_choice).assertEqual('auto');
      expect(req.tools.length).assertEqual(TOOLS.length);
      expect(req.tools[0].type).assertEqual('function');
      expect(req.tools[0].function.name).assertEqual(TOOLS[0].name);
    });

    it('maps tool_calls to tool_use blocks', 0, () => {
      const r = parseOpenAiResponse('{"id":"chatcmpl-1","model":"gpt-5","choices":[{"finish_reason":"tool_calls",' +
        '"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_9","type":"function",' +
        '"function":{"name":"click","arguments":"{\\"index\\": 4}"}}]}}]}');
      expect(r.stop_reason).assertEqual('tool_use');
      expect(r.content.length).assertEqual(1);
      expect(r.content[0].type).assertEqual('tool_use');
      expect(r.content[0].id).assertEqual('call_9');
      expect(r.content[0].input?.['index'] as number).assertEqual(4);
    });

    it('turns malformed tool arguments into a validator error, not a crash', 0, () => {
      const r = parseOpenAiResponse('{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant",' +
        '"tool_calls":[{"id":"call_1","type":"function","function":{"name":"click","arguments":"{index: 4"}}]}}]}');
      expect(r.content[0].input).assertUndefined();
      expect(parseToolCall(r.content[0]).error).assertContain('JSON object');
    });

    it('maps finish reasons and refusals', 0, () => {
      expect(parseOpenAiResponse('{"choices":[{"finish_reason":"stop","message":{"role":"assistant",' +
        '"content":"Done."}}]}').stop_reason).assertEqual('end_turn');
      expect(parseOpenAiResponse('{"choices":[{"finish_reason":"length","message":{"role":"assistant",' +
        '"content":"..."}}]}').stop_reason).assertEqual('max_tokens');
      expect(parseOpenAiResponse('{"choices":[{"finish_reason":"content_filter","message":{"role":"assistant",' +
        '"content":""}}]}').stop_reason).assertEqual('refusal');
      expect(parseOpenAiResponse('{"choices":[{"finish_reason":"stop","message":{"role":"assistant",' +
        '"content":null,"refusal":"I cannot help with that."}}]}').stop_reason).assertEqual('refusal');
    });

    it('rejects responses without choices', 0, () => {
      let typed = false;
      try {
        parseOpenAiResponse('{"choices":[]}');
      } catch (e) {
        typed = e instanceof LlmError && (e as LlmError).errorType === 'invalid_response';
      }
      expect(typed).assertTrue();
    });

    it('maps API errors', 0, () => {
      const auth = parseOpenAiError(401, '{"error":{"message":"Incorrect API key provided","type":"invalid_request_error",' +
        '"code":"invalid_api_key"}}');
      expect(auth.errorType).assertEqual('authentication_error');
      expect(auth.retryable).assertFalse();
      const quota = parseOpenAiError(429, '{"error":{"message":"You exceeded your current quota","type":"insufficient_quota",' +
        '"code":"insufficient_quota"}}');
      expect(quota.errorType).assertEqual('billing_error');
      expect(quota.retryable).assertFalse();
      expect(parseOpenAiError(429, '{"error":{"message":"Rate limit reached","code":"rate_limit_exceeded"}}').retryable)
        .assertTrue();
      expect(parseOpenAiError(404, '{"error":{"message":"The model does not exist"}}').errorType)
        .assertEqual('not_found_error');
      expect(parseOpenAiError(503, 'Service Unavailable').retryable).assertTrue();
    });

    it('maps the real invalid-key responses of OpenAI and xAI (captured live)', 0, () => {
      const openai = parseOpenAiError(401, '{"error":{"message":"Incorrect API key provided: dummy-ke****heck.",' +
        '"type":"invalid_request_error","param":null,"code":"invalid_api_key"}}');
      expect(openai.errorType).assertEqual('authentication_error');
      expect(openai.message).assertContain('Incorrect API key');
      // xAI: string "error", status 400
      const xai = parseOpenAiError(400, '{"code":"invalid-argument","error":"Incorrect API key provided. ' +
        'You can obtain an API key from https://console.x.ai."}');
      expect(xai.errorType).assertEqual('authentication_error');
      expect(xai.retryable).assertFalse();
      expect(xai.message).assertContain('Incorrect API key');
      // other 400s stay request errors
      expect(parseOpenAiError(400, '{"code":"invalid-argument","error":"Unknown model grok-x"}').errorType)
        .assertEqual('invalid_request_error');
    });
  });
}
