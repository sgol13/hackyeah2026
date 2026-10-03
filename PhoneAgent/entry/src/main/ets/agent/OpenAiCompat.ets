/**
 * Client for OpenAI-compatible Chat Completions APIs (POST /v1/chat/completions
 * with function tools): used for OpenAI and xAI (Grok), which share the format.
 *
 * Translates the agent's conversation format (Anthropic-style content blocks) to
 * chat messages and back:
 *   assistant text + tool_use blocks  <-> assistant message with content + tool_calls
 *   user tool_result blocks           <-> one role:"tool" message per call
 * Implemented against the public API documentation; not exercised against the
 * live endpoints in this project (no keys), but covered by unit tests.
 */
import { ApiMessage, ChatClient, ContentBlock, JsonSchema, MessagesResponse, ToolDef } from './Anthropic';
import { errorTypeForStatus, HttpResponse, isRetryableStatus, LlmError, postWithRetry } from './Http';

export const OPENAI_CHAT_URL = 'https://api.openai.com/v1/chat/completions';
export const XAI_CHAT_URL = 'https://api.x.ai/v1/chat/completions';

// ---------- wire types ----------

export interface OaFunction {
  name: string;
  description: string;
  parameters: JsonSchema;
}

export interface OaTool {
  type: string;
  function: OaFunction;
}

export interface OaToolCallFunction {
  name: string;
  arguments: string;
}

export interface OaToolCall {
  id: string;
  type: string;
  function: OaToolCallFunction;
}

export interface OaMessage {
  role: string;
  content?: string | null;
  tool_calls?: OaToolCall[];
  tool_call_id?: string;
  refusal?: string | null;
}

export interface OaRequest {
  model: string;
  messages: OaMessage[];
  tools: OaTool[];
  tool_choice: string;
  /** OpenAI and xAI both take reasoning_effort in Chat Completions */
  reasoning_effort?: string;
}

interface OaChoice {
  message: OaMessage;
  finish_reason?: string;
}

interface OaResponse {
  id?: string;
  model?: string;
  choices?: OaChoice[];
}

// ---------- requests ----------

export function toOpenAiTools(tools: ToolDef[]): OaTool[] {
  return tools.map((t: ToolDef): OaTool => {
    return { type: 'function', function: { name: t.name, description: t.description, parameters: t.input_schema } };
  });
}

function textOf(blocks: ContentBlock[]): string {
  return blocks.filter((b: ContentBlock) => b.type === 'text' && b.text !== undefined)
    .map((b: ContentBlock) => b.text as string)
    .join('\n');
}

/** Converts the agent conversation into chat messages (system prompt first). */
export function toOpenAiMessages(system: string, messages: ApiMessage[]): OaMessage[] {
  const out: OaMessage[] = [{ role: 'system', content: system }];
  for (const m of messages) {
    if (m.role === 'assistant') {
      const calls: OaToolCall[] = m.content.filter((b: ContentBlock) => b.type === 'tool_use')
        .map((b: ContentBlock): OaToolCall => {
          return {
            id: b.id ?? '',
            type: 'function',
            function: { name: b.name ?? '', arguments: JSON.stringify(b.input ?? {}) }
          };
        });
      const text = textOf(m.content);
      const msg: OaMessage = { role: 'assistant' };
      if (text.length > 0 || calls.length === 0) {
        msg.content = text;
      }
      if (calls.length > 0) {
        msg.tool_calls = calls;
      }
      out.push(msg);
      continue;
    }
    // user turn: tool results first (they must directly follow the assistant tool_calls), then text
    for (const b of m.content) {
      if (b.type === 'tool_result') {
        const content = b.content ?? '';
        out.push({ role: 'tool', tool_call_id: b.tool_use_id ?? '', content: b.is_error ? `ERROR: ${content}` : content });
      }
    }
    const text = textOf(m.content);
    if (text.length > 0) {
      out.push({ role: 'user', content: text });
    }
  }
  return out;
}

/** `effort` '' leaves reasoning_effort out (model default / models without the setting). */
export function buildOpenAiRequest(model: string, system: string, tools: ToolDef[],
  messages: ApiMessage[], effort: string = ''): OaRequest {
  const req: OaRequest = {
    model: model, messages: toOpenAiMessages(system, messages), tools: toOpenAiTools(tools), tool_choice: 'auto'
  };
  if (effort.length > 0) {
    req.reasoning_effort = effort;
  }
  return req;
}

// ---------- responses ----------

function parseArguments(raw: string): Record<string, Object> | undefined {
  try {
    const v = JSON.parse(raw) as Object;
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
      return v as Record<string, Object>;
    }
  } catch (e) {
    // malformed arguments: left undefined, the tool validator reports it to the model
  }
  return undefined;
}

/** Parses a 200 response into the agent's response format (exported for tests). */
export function parseOpenAiResponse(body: string): MessagesResponse {
  let parsed: OaResponse;
  try {
    parsed = JSON.parse(body) as OaResponse;
  } catch (e) {
    throw new LlmError(200, 'invalid_response', 'Response is not valid JSON', true);
  }
  if (!parsed || !Array.isArray(parsed.choices) || parsed.choices.length === 0 || !parsed.choices[0].message) {
    throw new LlmError(200, 'invalid_response', 'Response has no choices', true);
  }
  const choice = parsed.choices[0];
  const msg = choice.message;
  const content: ContentBlock[] = [];
  if (typeof msg.content === 'string' && msg.content.trim().length > 0) {
    content.push({ type: 'text', text: msg.content });
  }
  if (typeof msg.refusal === 'string' && msg.refusal.length > 0) {
    content.push({ type: 'text', text: msg.refusal });
  }
  const calls = msg.tool_calls ?? [];
  for (const c of calls) {
    const block: ContentBlock = { type: 'tool_use', id: c.id, name: c.function ? c.function.name : '' };
    const input = c.function ? parseArguments(c.function.arguments) : undefined;
    if (input !== undefined) {
      block.input = input;
    }
    content.push(block);
  }
  let stop = 'end_turn';
  if ((typeof msg.refusal === 'string' && msg.refusal.length > 0) || choice.finish_reason === 'content_filter') {
    stop = 'refusal';
  } else if (choice.finish_reason === 'length') {
    stop = 'max_tokens';
  } else if (calls.length > 0) {
    stop = 'tool_use';
  }
  return { id: parsed.id ?? '', model: parsed.model ?? '', stop_reason: stop, content: content };
}

function str(v: Object | undefined): string {
  return typeof v === 'string' ? v as string : '';
}

/**
 * Maps an error response of OpenAI / xAI onto LlmError (exported for tests). Shapes seen live:
 *   OpenAI: 401 {"error":{"message":"Incorrect API key provided...","type":"...","code":"invalid_api_key"}}
 *   xAI:    400 {"code":"invalid-argument","error":"Incorrect API key provided..."}
 */
export function parseOpenAiError(status: number, body: string): LlmError {
  let message = `HTTP ${status}`;
  let code = '';
  try {
    const parsed = JSON.parse(body) as Record<string, Object>;
    const err = parsed ? parsed['error'] : undefined;
    if (typeof err === 'string') {
      message = err as string;
      code = str(parsed['code']);
    } else if (err !== undefined && err !== null && typeof err === 'object') {
      const detail = err as Record<string, Object>;
      message = str(detail['message']) || message;
      code = str(detail['code']) || str(detail['type']);
    }
  } catch (e) {
    if (body.length > 0) {
      message = `HTTP ${status}: ${body.substring(0, 200)}`;
    }
  }
  if (code === 'insufficient_quota') {
    return new LlmError(status, 'billing_error', message, false);
  }
  if (code === 'invalid_api_key' || (status === 400 && /api key/i.test(message))) {
    return new LlmError(status, 'authentication_error', message, false);
  }
  return new LlmError(status, errorTypeForStatus(status), message, isRetryableStatus(status));
}

function handleResponse(resp: HttpResponse): MessagesResponse {
  if (resp.status >= 200 && resp.status < 300) {
    return parseOpenAiResponse(resp.body);
  }
  throw parseOpenAiError(resp.status, resp.body);
}

// ---------- client ----------

export class OpenAiCompatClient implements ChatClient {
  private url: string;
  private apiKey: string;
  private model: string;
  private effort: string;

  constructor(url: string, apiKey: string, model: string, effort: string = '') {
    this.url = url;
    this.apiKey = apiKey;
    this.model = model;
    this.effort = effort;
  }

  createMessage(system: string, tools: ToolDef[], messages: ApiMessage[]): Promise<MessagesResponse> {
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'authorization': `Bearer ${this.apiKey}`
    };
    const body = JSON.stringify(buildOpenAiRequest(this.model, system, tools, messages, this.effort));
    return postWithRetry<MessagesResponse>(this.url, headers, body, handleResponse);
  }
}
