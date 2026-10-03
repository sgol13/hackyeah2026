/**
 * The agent loop: ask the model what to do, validate and run its tool calls on
 * the phone, feed results (including the new screen) back, repeat until the
 * model calls finish or a limit is hit.
 *
 * Device access and the LLM are behind interfaces so the loop is unit-testable.
 * The message history is append-only (required for thinking blocks and keeps
 * the prompt cache warm).
 */
import { ApiMessage, ContentBlock, MessagesResponse } from './Anthropic';
import { LlmError } from './Http';
import {
  parseToolCall,
  TOOL_CLICK,
  TOOL_FINISH,
  TOOL_LAUNCH_APP,
  TOOL_LIST_APPS,
  TOOL_PRESS_KEY,
  TOOL_READ_SCREEN,
  TOOL_SCROLL,
  TOOL_TYPE_TEXT,
  ToolAction
} from './Tools';

export interface Executor {
  /** "Name (bundle)" per line */
  listApps(): Promise<string>;
  launchApp(bundleName: string): Promise<void>;
  /** Re-reads the screen; indexes in the returned text are valid until the next call. */
  readScreen(): Promise<string>;
  /** Human-readable line for an element of the last screen ('' if unknown). */
  describeElement(index: number): string;
  click(index: number): Promise<void>;
  typeText(index: number, text: string): Promise<void>;
  scroll(index: number, down: boolean): Promise<void>;
  pressKey(key: string): Promise<void>;
  /** Waits for the UI to settle after an action. */
  settle(): Promise<void>;
}

export interface Llm {
  send(messages: ApiMessage[]): Promise<MessagesResponse>;
}

export const LOG_TASK = 'task';
export const LOG_THOUGHT = 'thought';
export const LOG_ACTION = 'action';
export const LOG_ERROR = 'error';
export const LOG_DONE = 'done';

export interface AgentListener {
  log(kind: string, text: string): void;
}

export interface AgentResult {
  success: boolean;
  summary: string;
  steps: number;
}

const DEFAULT_MAX_STEPS = 25;
const MAX_NUDGES = 1;
const NUDGE_TEXT = 'Continue the task using the tools. When it is complete (or impossible), call finish.';

function textBlock(text: string): ContentBlock {
  return { type: 'text', text: text };
}

function toolResult(toolUseId: string, content: string, isError: boolean): ContentBlock {
  const block: ContentBlock = { type: 'tool_result', tool_use_id: toolUseId, content: content };
  if (isError) {
    block.is_error = true;
  }
  return block;
}

/** User-facing description of an API failure (any provider). */
export function describeApiError(e: LlmError): string {
  switch (e.errorType) {
    case 'authentication_error':
      return 'The API key was rejected. Check it in the settings.';
    case 'permission_error':
    case 'not_found_error':
      return `The selected model is not available for this API key (${e.message}).`;
    case 'rate_limit_error':
      return 'Rate limited by the AI provider. Try again in a minute.';
    case 'overloaded_error':
      return 'The AI provider is overloaded. Try again shortly.';
    case 'billing_error':
      return `The AI provider account has no credit or quota left (${e.message}).`;
    case 'network_error':
      return `Cannot reach the AI provider. Check the internet connection. (${e.message})`;
    case 'invalid_response':
      return `Unexpected response from the API: ${e.message}`;
    default:
      return `API error ${e.status} ${e.errorType}: ${e.message}`;
  }
}

function errorMessage(e: Object): string {
  if (e instanceof Error) {
    return (e as Error).message;
  }
  const be = e as Record<string, Object>;
  if (be && be['message'] !== undefined) {
    return `${be['message']} (code ${be['code']})`;
  }
  return String(e);
}

export class AgentLoop {
  private llm: Llm;
  private exec: Executor;
  private listener: AgentListener;
  private maxSteps: number;
  private stopped: boolean = false;

  constructor(llm: Llm, exec: Executor, listener: AgentListener, maxSteps: number = DEFAULT_MAX_STEPS) {
    this.llm = llm;
    this.exec = exec;
    this.listener = listener;
    this.maxSteps = maxSteps;
  }

  stop(): void {
    this.stopped = true;
  }

  private end(success: boolean, summary: string, steps: number): AgentResult {
    this.listener.log(success ? LOG_DONE : LOG_ERROR, summary);
    return { success: success, summary: summary, steps: steps };
  }

  async run(task: string): Promise<AgentResult> {
    this.listener.log(LOG_TASK, task);
    let apps = '';
    try {
      apps = await this.exec.listApps();
    } catch (e) {
      apps = '(could not list apps: ' + errorMessage(e as Object) + ')';
    }
    const messages: ApiMessage[] = [
      { role: 'user', content: [textBlock(`Task: ${task}\n\nInstalled apps:\n${apps}`)] }
    ];
    let nudges = 0;
    for (let step = 1; step <= this.maxSteps; step++) {
      if (this.stopped) {
        return this.end(false, 'Stopped by the user.', step - 1);
      }
      let resp: MessagesResponse;
      try {
        resp = await this.llm.send(messages);
      } catch (e) {
        const msg = e instanceof LlmError ? describeApiError(e as LlmError) : errorMessage(e as Object);
        return this.end(false, msg, step - 1);
      }
      // Append the full content (incl. thinking/fallback blocks) unchanged.
      messages.push({ role: 'assistant', content: resp.content });
      for (const b of resp.content) {
        if (b.type === 'text' && b.text && b.text.trim().length > 0) {
          this.listener.log(LOG_THOUGHT, b.text.trim());
        }
      }
      if (resp.stop_reason === 'refusal') {
        return this.end(false, 'The model declined this request.', step);
      }
      if (resp.stop_reason === 'max_tokens') {
        return this.end(false, 'The model response was cut off (max_tokens); nothing was executed.', step);
      }
      const toolUses = resp.content.filter((b: ContentBlock) => b.type === 'tool_use');
      if (toolUses.length === 0) {
        if (nudges < MAX_NUDGES) {
          nudges++;
          messages.push({ role: 'user', content: [textBlock(NUDGE_TEXT)] });
          continue;
        }
        return this.end(false, 'The model stopped without finishing the task.', step);
      }

      const results: ContentBlock[] = [];
      let finished: AgentResult | undefined = undefined;
      for (const tu of toolUses) {
        const id = tu.id ?? '';
        if (finished !== undefined || this.stopped) {
          results.push(toolResult(id, 'Not executed: the task has ended.', true));
          continue;
        }
        const parsed = parseToolCall(tu);
        if (parsed.action === undefined) {
          const err = parsed.error ?? 'Invalid tool call';
          this.listener.log(LOG_ERROR, `Invalid tool call ${tu.name}: ${err}`);
          results.push(toolResult(id, err, true));
          continue;
        }
        const action = parsed.action;
        if (action.name === TOOL_FINISH) {
          finished = this.end(action.success, action.text, step);
          results.push(toolResult(id, 'Task ended.', false));
          continue;
        }
        this.listener.log(LOG_ACTION, this.describe(action));
        try {
          results.push(toolResult(id, await this.execute(action), false));
        } catch (e) {
          const msg = errorMessage(e as Object);
          this.listener.log(LOG_ERROR, msg);
          let screen = '';
          try {
            screen = await this.exec.readScreen();
          } catch (e2) {
            screen = '(screen unavailable)';
          }
          results.push(toolResult(id, `${msg}\n\nCurrent screen:\n${screen}`, true));
        }
      }
      // All tool results of one assistant turn go back in a single user message.
      messages.push({ role: 'user', content: results });
      if (finished !== undefined) {
        return finished;
      }
    }
    return this.end(false, `Stopped after ${this.maxSteps} steps without finishing.`, this.maxSteps);
  }

  private describe(a: ToolAction): string {
    const el = a.index >= 0 ? this.exec.describeElement(a.index) : '';
    switch (a.name) {
      case TOOL_LIST_APPS:
        return 'List apps';
      case TOOL_LAUNCH_APP:
        return `Open ${a.bundleName}`;
      case TOOL_READ_SCREEN:
        return 'Read screen';
      case TOOL_CLICK:
        return `Tap ${el.length > 0 ? el : '[' + a.index + ']'}`;
      case TOOL_TYPE_TEXT:
        return `Type "${a.text}" into ${el.length > 0 ? el : '[' + a.index + ']'}`;
      case TOOL_SCROLL:
        return `Scroll ${a.scrollDown ? 'down' : 'up'} ${el.length > 0 ? el : '[' + a.index + ']'}`;
      case TOOL_PRESS_KEY:
        return `Press ${a.key}`;
      default:
        return a.name;
    }
  }

  private async afterAction(prefix: string): Promise<string> {
    await this.exec.settle();
    return `${prefix}\n${await this.exec.readScreen()}`;
  }

  private async execute(a: ToolAction): Promise<string> {
    switch (a.name) {
      case TOOL_LIST_APPS:
        return await this.exec.listApps();
      case TOOL_LAUNCH_APP:
        await this.exec.launchApp(a.bundleName);
        return await this.afterAction(`Opened ${a.bundleName}. Screen:`);
      case TOOL_READ_SCREEN:
        return await this.exec.readScreen();
      case TOOL_CLICK:
        await this.exec.click(a.index);
        return await this.afterAction(`Tapped [${a.index}]. New screen:`);
      case TOOL_TYPE_TEXT:
        await this.exec.typeText(a.index, a.text);
        return await this.afterAction(`Typed into [${a.index}]. New screen:`);
      case TOOL_SCROLL:
        await this.exec.scroll(a.index, a.scrollDown);
        return await this.afterAction(`Scrolled [${a.index}]. New screen:`);
      case TOOL_PRESS_KEY:
        await this.exec.pressKey(a.key);
        return await this.afterAction(`Pressed ${a.key}. New screen:`);
      default:
        throw new Error(`Unsupported tool ${a.name}`);
    }
  }
}
