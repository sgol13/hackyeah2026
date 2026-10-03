import { describe, expect, it } from '@ohos/hypium';
import { AnthropicError, ApiMessage, ContentBlock, MessagesResponse } from '../../../main/ets/agent/Anthropic';
import { AgentListener, AgentLoop, Executor, Llm, LOG_ERROR } from '../../../main/ets/agent/AgentLoop';

// ---------- fakes ----------

/** Replays scripted responses and records every request it receives. */
class FakeLlm implements Llm {
  responses: MessagesResponse[] = [];
  error: AnthropicError | undefined = undefined;
  requests: string[] = [];

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    this.requests.push(JSON.stringify(messages));
    if (this.error !== undefined) {
      return Promise.reject(this.error);
    }
    const next = this.responses.shift();
    if (next === undefined) {
      return Promise.reject(new Error('no scripted response left'));
    }
    return Promise.resolve(next);
  }
}

class FakeExecutor implements Executor {
  actions: string[] = [];
  screenItems: number = 5;

  listApps(): Promise<string> {
    return Promise.resolve('Messages (com.ohos.mms)\nSettings (com.ohos.settings)');
  }

  launchApp(bundleName: string): Promise<void> {
    this.actions.push(`launch ${bundleName}`);
    return Promise.resolve();
  }

  readScreen(): Promise<string> {
    return Promise.resolve('App: com.ohos.mms\n[0] Text "New message" @130,64');
  }

  describeElement(index: number): string {
    return `[${index}] Fake`;
  }

  click(index: number): Promise<void> {
    if (index >= this.screenItems) {
      return Promise.reject(new Error(`Index ${index} is not on the current screen`));
    }
    this.actions.push(`click ${index}`);
    return Promise.resolve();
  }

  typeText(index: number, text: string): Promise<void> {
    this.actions.push(`type ${index} ${text}`);
    return Promise.resolve();
  }

  scroll(index: number, down: boolean): Promise<void> {
    this.actions.push(`scroll ${index} ${down}`);
    return Promise.resolve();
  }

  pressKey(key: string): Promise<void> {
    this.actions.push(`key ${key}`);
    return Promise.resolve();
  }

  settle(): Promise<void> {
    return Promise.resolve();
  }
}

class RecordingListener implements AgentListener {
  kinds: string[] = [];

  log(kind: string, text: string): void {
    this.kinds.push(kind);
  }
}

// ---------- response builders ----------

function toolUse(id: string, name: string, input: Record<string, Object>): ContentBlock {
  return { type: 'tool_use', id: id, name: name, input: input };
}

function reply(stopReason: string, content: ContentBlock[]): MessagesResponse {
  return { id: 'msg', model: 'claude-opus-5-5', stop_reason: stopReason, content: content };
}

function finish(id: string): MessagesResponse {
  return reply('tool_use', [toolUse(id, 'finish', { 'success': true, 'summary': 'Done.' })]);
}

/** tool_result blocks of the last user message in a recorded request */
function lastToolResults(request: string): ContentBlock[] {
  const messages = JSON.parse(request) as ApiMessage[];
  return messages[messages.length - 1].content;
}

function setup(): [FakeLlm, FakeExecutor, RecordingListener, AgentLoop] {
  const llm = new FakeLlm();
  const exec = new FakeExecutor();
  const listener = new RecordingListener();
  return [llm, exec, listener, new AgentLoop(llm, exec, listener, 6)];
}

export default function agentLoopTest() {
  describe('AgentLoop', () => {
    it('runs tool calls in order and finishes', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('tool_use', [
          { type: 'thinking', thinking: '', signature: 'sig-1' },
          toolUse('t1', 'launch_app', { 'bundle_name': 'com.ohos.mms' })
        ]),
        reply('tool_use', [toolUse('t2', 'click', { 'index': 0 }), toolUse('t3', 'type_text', { 'index': 1, 'text': 'Hi' })]),
        finish('t4')
      ];
      const result = await s[3].run('text grandma');
      expect(result.success).assertTrue();
      expect(result.summary).assertEqual('Done.');
      expect(s[1].actions.join('|')).assertEqual('launch com.ohos.mms|click 0|type 1 Hi');
      // Both results of the parallel calls go back in one user message, matched by id.
      const results = lastToolResults(s[0].requests[2]);
      expect(results.length).assertEqual(2);
      expect(results[0].tool_use_id).assertEqual('t2');
      expect(results[1].tool_use_id).assertEqual('t3');
      expect(results[0].content).assertContain('New screen');
      // The thinking block is echoed back unchanged (append-only history).
      expect(s[0].requests[1]).assertContain('"signature":"sig-1"');
    });

    it('returns invalid tool input to the model as is_error and keeps going', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('tool_use', [toolUse('t1', 'click', { 'index': 'second button' })]),
        reply('tool_use', [toolUse('t2', 'teleport', {})]),
        finish('t3')
      ];
      const result = await s[3].run('task');
      expect(result.success).assertTrue();
      expect(s[1].actions.length).assertEqual(0);
      const first = lastToolResults(s[0].requests[1])[0];
      expect(first.is_error).assertTrue();
      expect(first.content).assertContain('integer');
      const second = lastToolResults(s[0].requests[2])[0];
      expect(second.is_error).assertTrue();
      expect(second.content).assertContain('Unknown tool');
      expect(s[2].kinds.indexOf(LOG_ERROR) >= 0).assertTrue();
    });

    it('reports device failures with the current screen so the model can recover', 0, async () => {
      const s = setup();
      s[0].responses = [reply('tool_use', [toolUse('t1', 'click', { 'index': 42 })]), finish('t2')];
      await s[3].run('task');
      const res = lastToolResults(s[0].requests[1])[0];
      expect(res.is_error).assertTrue();
      expect(res.content).assertContain('not on the current screen');
      expect(res.content).assertContain('Current screen:');
    });

    it('stops on refusal without executing tools', 0, async () => {
      const s = setup();
      s[0].responses = [reply('refusal', [toolUse('t1', 'click', { 'index': 0 })])];
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(s[1].actions.length).assertEqual(0);
    });

    it('does not execute a truncated (max_tokens) turn', 0, async () => {
      const s = setup();
      s[0].responses = [reply('max_tokens', [toolUse('t1', 'click', { 'index': 0 })])];
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(s[1].actions.length).assertEqual(0);
    });

    it('nudges once when the model answers without tools, then gives up', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('end_turn', [{ type: 'text', text: 'Which grandma?' }]),
        reply('end_turn', [{ type: 'text', text: 'I need more info.' }])
      ];
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(s[0].requests.length).assertEqual(2);
      expect(s[0].requests[1]).assertContain('call finish');
    });

    it('enforces the step limit', 0, async () => {
      const s = setup();
      for (let i = 0; i < 10; i++) {
        s[0].responses.push(reply('tool_use', [toolUse(`t${i}`, 'read_screen', {})]));
      }
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(result.summary).assertContain('6 steps');
      expect(s[0].requests.length).assertEqual(6);
    });

    it('turns API errors into a readable message', 0, async () => {
      const s = setup();
      s[0].error = new AnthropicError(401, 'authentication_error', 'invalid x-api-key', false);
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(result.summary).assertContain('API key was rejected');
    });

    it('can be stopped by the user', 0, async () => {
      const s = setup();
      s[0].responses = [reply('tool_use', [toolUse('t1', 'read_screen', {})]), finish('t2')];
      s[3].stop();
      const result = await s[3].run('task');
      expect(result.summary).assertContain('Stopped');
      expect(s[0].requests.length).assertEqual(0);
    });
  });
}
