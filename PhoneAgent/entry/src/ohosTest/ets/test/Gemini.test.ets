import { describe, expect, it } from '@ohos/hypium';
import { ApiMessage } from '../../../main/ets/agent/Anthropic';
import {
  buildGeminiRequest,
  parseGeminiError,
  parseGeminiResponse,
  SYNTHETIC_ID_PREFIX,
  toGeminiContents,
  toGeminiTools
} from '../../../main/ets/agent/Gemini';
import { TOOLS } from '../../../main/ets/agent/Tools';

export default function geminiTest() {
  describe('Gemini client', () => {
    it('declares tools in Gemini schema form', 0, () => {
      const decls = toGeminiTools(TOOLS)[0].functionDeclarations;
      expect(decls.length).assertEqual(TOOLS.length);
      const listApps = decls.find(d => d.name === 'list_apps');
      expect(listApps?.parameters).assertUndefined(); // no empty object schemas
      const click = decls.find(d => d.name === 'click');
      expect(click?.parameters?.type).assertEqual('object');
      expect(click?.parameters?.required?.[0]).assertEqual('index');
      expect(JSON.stringify(decls)).not().assertContain('additionalProperties');
    });

    it('maps calls to the model and results back to the user with the tool name', 0, () => {
      const msgs: ApiMessage[] = [
        { role: 'user', content: [{ type: 'text', text: 'Task: open settings' }] },
        {
          role: 'assistant', content: [
          { type: 'text', text: 'Opening.', thought_signature: 'sig-A' },
          { type: 'tool_use', id: `${SYNTHETIC_ID_PREFIX}1`, name: 'launch_app', input: { 'bundle_name': 'com.ohos.settings' } },
          { type: 'tool_use', id: 'fc-42', name: 'click', input: { 'index': 2 } }
        ]
        },
        {
          role: 'user', content: [
          { type: 'tool_result', tool_use_id: `${SYNTHETIC_ID_PREFIX}1`, content: 'Opened.' },
          { type: 'tool_result', tool_use_id: 'fc-42', content: 'not on screen', is_error: true }
        ]
        }
      ];
      const contents = toGeminiContents(msgs);
      expect(contents[1].role).assertEqual('model');
      expect(contents[1].parts[0].thoughtSignature).assertEqual('sig-A');
      expect(contents[1].parts[1].functionCall?.name).assertEqual('launch_app');
      expect(contents[1].parts[1].functionCall?.id).assertUndefined(); // synthetic IDs are not sent
      expect(contents[1].parts[2].functionCall?.id).assertEqual('fc-42');
      expect(contents[2].role).assertEqual('user');
      expect(contents[2].parts[0].functionResponse?.name).assertEqual('launch_app');
      expect(contents[2].parts[0].functionResponse?.response['result'] as string).assertEqual('Opened.');
      expect(contents[2].parts[1].functionResponse?.response['error'] as string).assertEqual('not on screen');
      expect(contents[2].parts[1].functionResponse?.id).assertEqual('fc-42');
      const req = buildGeminiRequest('SYSTEM', TOOLS, msgs);
      expect(req.systemInstruction.parts[0].text).assertEqual('SYSTEM');
      expect(req.toolConfig.functionCallingConfig.mode).assertEqual('AUTO');
    });

    it('maps effort to a thinking level', 0, () => {
      const msgs: ApiMessage[] = [{ role: 'user', content: [{ type: 'text', text: 'Task: x' }] }];
      expect(buildGeminiRequest('SYSTEM', TOOLS, msgs, 'low').generationConfig?.thinkingConfig.thinkingLevel)
        .assertEqual('LOW');
      expect(buildGeminiRequest('SYSTEM', TOOLS, msgs, 'none').generationConfig).assertUndefined();
      expect(buildGeminiRequest('SYSTEM', TOOLS, msgs).generationConfig).assertUndefined();
    });

    it('parses function calls, thoughts and signatures', 0, () => {
      const r = parseGeminiResponse('{"candidates":[{"finishReason":"STOP","content":{"role":"model","parts":[' +
        '{"text":"thinking about it","thought":true},' +
        '{"functionCall":{"name":"click","args":{"index":5}},"thoughtSignature":"sig-B"}]}}],' +
        '"modelVersion":"gemini-2.5-flash"}');
      expect(r.stop_reason).assertEqual('tool_use');
      expect(r.content[0].type).assertEqual('thinking');
      expect(r.content[1].type).assertEqual('tool_use');
      expect(r.content[1].name).assertEqual('click');
      expect(r.content[1].input?.['index'] as number).assertEqual(5);
      expect(r.content[1].id?.startsWith(SYNTHETIC_ID_PREFIX)).assertTrue();
      expect(r.content[1].thought_signature).assertEqual('sig-B');
      // round trip: the model turn goes back with the thought part and the signature
      const back = toGeminiContents([{ role: 'assistant', content: r.content }]);
      expect(back[0].parts[0].thought).assertTrue();
      expect(back[0].parts[1].thoughtSignature).assertEqual('sig-B');
    });

    it('maps finish reasons and blocked prompts', 0, () => {
      expect(parseGeminiResponse('{"candidates":[{"finishReason":"STOP","content":{"role":"model",' +
        '"parts":[{"text":"Done."}]}}]}').stop_reason).assertEqual('end_turn');
      expect(parseGeminiResponse('{"candidates":[{"finishReason":"MAX_TOKENS","content":{"role":"model",' +
        '"parts":[{"text":"..."}]}}]}').stop_reason).assertEqual('max_tokens');
      expect(parseGeminiResponse('{"candidates":[{"finishReason":"SAFETY"}]}').stop_reason).assertEqual('refusal');
      expect(parseGeminiResponse('{"promptFeedback":{"blockReason":"SAFETY"}}').stop_reason).assertEqual('refusal');
    });

    it('maps API errors', 0, () => {
      const badKey = parseGeminiError(400, '{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.",' +
        '"status":"INVALID_ARGUMENT"}}');
      expect(badKey.errorType).assertEqual('authentication_error');
      expect(badKey.retryable).assertFalse();
      const quota = parseGeminiError(429, '{"error":{"code":429,"message":"Resource has been exhausted",' +
        '"status":"RESOURCE_EXHAUSTED"}}');
      expect(quota.errorType).assertEqual('rate_limit_error');
      expect(quota.retryable).assertTrue();
      expect(parseGeminiError(404, '{"error":{"code":404,"message":"models/x is not found","status":"NOT_FOUND"}}')
        .errorType).assertEqual('not_found_error');
      expect(parseGeminiError(503, '{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}')
        .errorType).assertEqual('overloaded_error');
    });
  });
}
