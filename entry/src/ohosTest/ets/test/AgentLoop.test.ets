import { describe, expect, it } from '@ohos/hypium';
import { ApiMessage, ContentBlock, MessagesResponse } from '../../../main/ets/agent/Anthropic';
import { LlmError } from '../../../main/ets/agent/Http';
import { AgentListener, AgentLoop, Executor, Llm, LOG_ERROR } from '../../../main/ets/agent/AgentLoop';
import { UserSkill } from '../../../main/ets/agent/Skills';

// ---------- fakes ----------

/** Replays scripted responses and records every request it receives. */
/** A model call that takes 10 s, to test stopping while waiting for the model. */
class SlowLlm implements Llm {
  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    return new Promise<MessagesResponse>((resolve) => {
      setTimeout(() => resolve({ id: 'm', model: 'x', stop_reason: 'end_turn', content: [] }), 10000);
    });
  }
}

class FakeLlm implements Llm {
  responses: MessagesResponse[] = [];
  error: LlmError | undefined = undefined;
  requests: string[] = [];
  /** never answer (a slow model call or one stuck in retries) */
  hang: boolean = false;
  onSend: () => void = () => {};

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    this.requests.push(JSON.stringify(messages));
    this.onSend();
    if (this.hang) {
      return new Promise<MessagesResponse>(() => {});
    }
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
  /** what readScreen returns; typing changes it, clicks do not */
  screen: string = 'App: com.ohos.mms\n[0] Text "New message" @130,64';

  listApps(): Promise<string> {
    return Promise.resolve('Messages (com.ohos.mms)\nSettings (com.ohos.settings)');
  }

  launchApp(bundleName: string): Promise<void> {
    this.actions.push(`launch ${bundleName}`);
    return Promise.resolve();
  }

  readScreen(): Promise<string> {
    return Promise.resolve(this.screen);
  }

  describeElement(index: number): string {
    return `[${index}] Fake`;
  }

  appLabel(bundleName: string): string {
    return bundleName === 'com.ohos.mms' ? 'Messages' : '';
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
    this.screen += `\n[${index}] TextArea "${text}" (click,edit) @164,659`;
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

  setAlarm(hour: number, minute: number, label: string): Promise<string> {
    this.actions.push(`alarm ${hour}:${minute} ${label}`);
    return Promise.resolve(`Alarm set for ${hour}:${minute}.`);
  }
}

class RecordingListener implements AgentListener {
  kinds: string[] = [];
  texts: string[] = [];

  log(kind: string, text: string): void {
    this.kinds.push(kind);
    this.texts.push(text);
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

function hasNoEffectNote(request: string): boolean {
  return (lastToolResults(request)[0].content ?? '').indexOf('did not change') >= 0;
}

function setup():[FakeLlm, FakeExecutor, RecordingListener, AgentLoop] {
  const llm = new FakeLlm();
  const exec = new FakeExecutor();
  const listener = new RecordingListener();
  return [llm, exec, listener, new AgentLoop(llm, exec, listener, 6)];
}

export default function agentLoopTest() {
  describe('AgentLoop', () => {
    it('loads a skill body from the frozen snapshot without operating the device', 0, async () => {
      const s = setup();
      const skill: UserSkill = { id: '1', name: 'Calendar', description: 'Events', body: 'Use a 90-minute duration.', enabled: true };
      const loop = new AgentLoop(s[0], s[1], s[2], 6, [skill]);
      skill.body = 'Edited after starting';
      skill.enabled = false;
      s[0].responses = [reply('tool_use', [toolUse('r1', 'read_skill', { 'name': 'CALENDAR' })]), finish('f1')];
      const result = await loop.run('Create an event');
      expect(result.success).assertTrue();
      expect(result.steps).assertEqual(2);
      expect(s[1].actions.length).assertEqual(0);
      expect(s[2].texts).assertContain('Read skill: Calendar');
      const body = lastToolResults(s[0].requests[1])[0];
      expect(body.content).assertEqual('Use a 90-minute duration.');
      expect(body.is_error === true).assertFalse();
      expect(s[0].requests[0].includes('90-minute')).assertFalse();
    });

    it('returns tool errors for disabled and missing skills without exposing their bodies', 0, async () => {
      const s = setup();
      const skill: UserSkill = { id: '1', name: 'Hidden', description: 'Events', body: 'Private instructions', enabled: false };
      const loop = new AgentLoop(s[0], s[1], s[2], 6, [skill]);
      s[0].responses = [reply('tool_use', [toolUse('r1', 'read_skill', { 'name': 'Hidden' })]), finish('f1')];
      await loop.run('Task');
      const result = lastToolResults(s[0].requests[1])[0];
      expect(result.is_error).assertTrue();
      expect(result.content).assertContain('No enabled skills');
      expect(s[0].requests[1].includes('Private instructions')).assertFalse();
      expect(s[1].actions.length).assertEqual(0);
    });

    it('counts reading skills against the normal step limit', 0, async () => {
      const s = setup();
      const skill: UserSkill = { id: '1', name: 'Calendar', description: 'Events', body: 'Instructions', enabled: true };
      const loop = new AgentLoop(s[0], s[1], s[2], 1, [skill]);
      s[0].responses = [reply('tool_use', [toolUse('r1', 'read_skill', { 'name': 'Calendar' })]), finish('f1')];
      const result = await loop.run('Task');
      expect(result.success).assertFalse();
      expect(result.summary).assertContain('1 steps');
      expect(s[0].requests.length).assertEqual(1);
    });

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
      s[0].error = new LlmError(401, 'authentication_error', 'invalid x-api-key', false);
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(result.summary).assertContain('API key was rejected');
    });

    it('logs steps as plain sentences', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('tool_use', [toolUse('t1', 'launch_app', { 'bundle_name': 'com.ohos.mms' })]),
        finish('t2')
      ];
      await s[3].run('text grandma');
      expect(s[2].texts).assertContain('Open Messages');
    });

    it('sets an alarm through the executor without reading the screen', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('tool_use', [toolUse('t1', 'set_alarm', { 'hour': 19, 'minute': 0 })]),
        finish('t2')
      ];
      const result = await s[3].run('Ustaw alarm na 19:00');
      expect(result.success).assertTrue();
      expect(s[1].actions.join('|')).assertEqual('alarm 19:0 ');
      expect(s[2].texts).assertContain('Set an alarm for 19:00');
      expect(lastToolResults(s[0].requests[1])[0].content).assertContain('Alarm set');
    });

    it('stops immediately while waiting for the model', 0, async () => {
      const listener = new RecordingListener();
      const loop = new AgentLoop(new SlowLlm(), new FakeExecutor(), listener, 6);
      const started = Date.now();
      setTimeout(() => loop.stop(), 100);
      const result = await loop.run('task');
      expect(result.success).assertFalse();
      expect(result.summary).assertEqual('Stopped by the user.');
      expect(Date.now() - started < 2000).assertTrue();
      expect(listener.kinds[listener.kinds.length - 1]).assertEqual(LOG_ERROR);
    });

    it('can be stopped by the user', 0, async () => {
      const s = setup();
      s[0].responses = [reply('tool_use', [toolUse('t1', 'read_screen', {})]), finish('t2')];
      s[3].stop();
      const result = await s[3].run('task');
      expect(result.summary).assertContain('Stopped');
      expect(s[0].requests.length).assertEqual(0);
    });

    it('stops at once while a model call is still pending', 0, async () => {
      const s = setup();
      s[0].hang = true;
      s[0].onSend = () => s[3].stop();
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(result.summary).assertContain('Stopped by the user');
      expect(s[0].requests.length).assertEqual(1);
      expect(s[1].actions.length).assertEqual(0);
    });

    it('tells the model when an action changed nothing on the screen', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('tool_use', [toolUse('t1', 'launch_app', { 'bundle_name': 'com.ohos.mms' })]),
        reply('tool_use', [toolUse('t2', 'click', { 'index': 0 })]),
        reply('tool_use', [toolUse('t3', 'type_text', { 'index': 0, 'text': 'Hi' })]),
        finish('t4')
      ];
      await s[3].run('task');
      expect(hasNoEffectNote(s[0].requests[1])).assertFalse(); // launch
      expect(hasNoEffectNote(s[0].requests[2])).assertTrue(); // click, same screen
      expect(hasNoEffectNote(s[0].requests[3])).assertFalse(); // typing changed the screen
    });

    it('gives up after repeated actions that change nothing', 0, async () => {
      const s = setup();
      for (let i = 0; i < 6; i++) {
        s[0].responses.push(reply('tool_use', [toolUse(`t${i}`, 'click', { 'index': 0 })]));
      }
      const result = await s[3].run('task');
      expect(result.success).assertFalse();
      expect(result.summary).assertContain('changed nothing');
      // the first click changes the (not yet seen) screen, the next 4 do not
      expect(s[0].requests.length).assertEqual(5);
    });

    it('keeps going when the screen changes between ineffective actions', 0, async () => {
      const s = setup();
      const loop = new AgentLoop(s[0], s[1], s[2], 10);
      s[0].responses = [
        reply('tool_use', [toolUse('t1', 'launch_app', { 'bundle_name': 'com.ohos.mms' })]),
        reply('tool_use', [toolUse('t2', 'click', { 'index': 0 })]),
        reply('tool_use', [toolUse('t3', 'click', { 'index': 0 })]),
        reply('tool_use', [toolUse('t4', 'click', { 'index': 0 })]),
        reply('tool_use', [toolUse('t5', 'type_text', { 'index': 0, 'text': 'Hi' })]),
        reply('tool_use', [toolUse('t6', 'click', { 'index': 0 })]),
        finish('t7')
      ];
      const result = await loop.run('task');
      expect(result.success).assertTrue();
    });
  });
}
