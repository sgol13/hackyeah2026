/**
 * Debug builds only: a scripted stand-in for the model, so the device side
 * (launching apps from the service, reading real screens, tapping, the step log)
 * can be exercised end to end without an API key.
 * Task syntax: "#script <bundle.name> <text to tap>"
 *   1. launch_app(bundle)  2. click the first element whose line contains the text  3. finish
 */
import { ApiMessage, ContentBlock, MessagesResponse } from '../agent/Anthropic';
import { Llm } from '../agent/AgentLoop';

export const SCRIPT_PREFIX = '#script ';

function reply(block: ContentBlock): MessagesResponse {
  return { id: 'scripted', model: 'scripted', stop_reason: 'tool_use', content: [block] };
}

function toolUse(id: string, name: string, input: Record<string, Object>): ContentBlock {
  return { type: 'tool_use', id: id, name: name, input: input };
}

export class ScriptedLlm implements Llm {
  private bundle: string;
  private target: string;

  /** spec: "<bundle.name> <text to tap>" */
  constructor(spec: string) {
    const sep = spec.indexOf(' ');
    this.bundle = sep > 0 ? spec.substring(0, sep) : spec;
    this.target = sep > 0 ? spec.substring(sep + 1) : '';
  }

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    const step = messages.filter((m: ApiMessage) => m.role === 'assistant').length;
    if (step === 0) {
      return Promise.resolve(reply(toolUse('s0', 'launch_app', { 'bundle_name': this.bundle })));
    }
    const last = messages[messages.length - 1].content;
    const screen = last.length > 0 ? (last[0].content ?? '') : '';
    if (step === 1) {
      for (const line of screen.split('\n')) {
        const m = line.match(/^\[(\d+)\]/);
        if (m !== null && line.indexOf(this.target) >= 0) {
          return Promise.resolve(reply(toolUse('s1', 'click', { 'index': parseInt(m[1]) })));
        }
      }
      return Promise.resolve(reply(toolUse('s1', 'finish',
        { 'success': false, 'summary': `"${this.target}" not found on screen` })));
    }
    return Promise.resolve(reply(toolUse('s2', 'finish',
      { 'success': true, 'summary': `Tapped "${this.target}". Screen now:\n${screen}` })));
  }
}
