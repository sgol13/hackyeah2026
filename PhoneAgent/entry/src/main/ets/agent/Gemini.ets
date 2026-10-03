/**
 * Client for the Google Gemini API (POST .../v1beta/models/{model}:generateContent)
 * with function calling.
 *
 * Translates the agent's conversation format (Anthropic-style content blocks):
 *   assistant text / tool_use      <-> role "model" parts: text / functionCall
 *   user tool_result               <-> role "user" part: functionResponse (needs the tool name)
 *   Gemini thought summaries        -> kept as "thinking" blocks and sent back unchanged
 *   thoughtSignature on any part   <-> ContentBlock.thought_signature (must be returned)
 * Implemented against the public API documentation; not exercised against the
 * live endpoint in this project (no key), but covered by unit tests.
 */
import { ApiMessage, ChatClient, ContentBlock, JsonSchemaProperty, MessagesResponse, ToolDef } from './Anthropic';
import { errorTypeForStatus, HttpResponse, isRetryableStatus, LlmError, postWithRetry } from './Http';

const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models/';
/** IDs we invent for calls that came without one; never sent back to Gemini */
export const SYNTHETIC_ID_PREFIX = 'gemini-call-';

// ---------- wire types ----------

export interface GmFunctionCall {
  name: string;
  args?: Record<string, Object>;
  id?: string;
}

export interface GmFunctionResponse {
  name: string;
  response: Record<string, Object>;
  id?: string;
}

export interface GmPart {
  text?: string;
  thought?: boolean;
  thoughtSignature?: string;
  functionCall?: GmFunctionCall;
  functionResponse?: GmFunctionResponse;
}

export interface GmContent {
  role: string;
  parts: GmPart[];
}

export interface GmSchema {
  type: string;
  description?: string;
  enum?: string[];
  properties?: Record<string, GmSchema>;
  required?: string[];
}

export interface GmFunctionDeclaration {
  name: string;
  description: string;
  parameters?: GmSchema;
}

export interface GmTool {
  functionDeclarations: GmFunctionDeclaration[];
}

export interface GmFunctionCallingConfig {
  mode: string;
}

export interface GmToolConfig {
  functionCallingConfig: GmFunctionCallingConfig;
}

export interface GmSystemInstruction {
  parts: GmPart[];
}

export interface GmThinkingConfig {
  /** MINIMAL / LOW / MEDIUM / HIGH; Gemini 3 and later (older models reject it) */
  thinkingLevel: string;
}

export interface GmGenerationConfig {
  thinkingConfig: GmThinkingConfig;
}

export interface GmRequest {
  systemInstruction: GmSystemInstruction;
  contents: GmContent[];
  tools: GmTool[];
  toolConfig: GmToolConfig;
  generationConfig?: GmGenerationConfig;
}

interface GmCandidate {
  content?: GmContent;
  finishReason?: string;
}

interface GmPromptFeedback {
  blockReason?: string;
}

interface GmResponse {
  candidates?: GmCandidate[];
  promptFeedback?: GmPromptFeedback;
  modelVersion?: string;
  responseId?: string;
}

interface GmErrorDetail {
  code?: number;
  message?: string;
  status?: string;
}

interface GmErrorBody {
  error?: GmErrorDetail;
}

const REFUSAL_REASONS: string[] = ['SAFETY', 'RECITATION', 'BLOCKLIST', 'PROHIBITED_CONTENT', 'SPII', 'IMAGE_SAFETY'];

// ---------- requests ----------

function toGmProperty(p: JsonSchemaProperty): GmSchema {
  const s: GmSchema = { type: p.type };
  if (p.description) {
    s.description = p.description;
  }
  if (p.enum) {
    s.enum = p.enum;
  }
  return s;
}

/** Gemini's schema is an OpenAPI subset: no additionalProperties, no empty object schemas. */
export function toGeminiTools(tools: ToolDef[]): GmTool[] {
  const decls = tools.map((t: ToolDef): GmFunctionDeclaration => {
    const decl: GmFunctionDeclaration = { name: t.name, description: t.description };
    const names = Object.keys(t.input_schema.properties);
    if (names.length > 0) {
      const props: Record<string, GmSchema> = {};
      for (const n of names) {
        props[n] = toGmProperty(t.input_schema.properties[n]);
      }
      decl.parameters = { type: 'object', properties: props, required: t.input_schema.required };
    }
    return decl;
  });
  return [{ functionDeclarations: decls }];
}

function withSignature(part: GmPart, b: ContentBlock): GmPart {
  if (b.thought_signature) {
    part.thoughtSignature = b.thought_signature;
  }
  return part;
}

/** Converts the agent conversation into Gemini contents (exported for tests). */
export function toGeminiContents(messages: ApiMessage[]): GmContent[] {
  const toolNames: Record<string, string> = {};
  const out: GmContent[] = [];
  for (const m of messages) {
    const parts: GmPart[] = [];
    if (m.role === 'assistant') {
      for (const b of m.content) {
        if (b.type === 'text' && b.text !== undefined) {
          parts.push(withSignature({ text: b.text }, b));
        } else if (b.type === 'thinking') {
          parts.push(withSignature({ text: b.thinking ?? '', thought: true }, b));
        } else if (b.type === 'tool_use') {
          const id = b.id ?? '';
          toolNames[id] = b.name ?? '';
          const call: GmFunctionCall = { name: b.name ?? '', args: b.input ?? {} };
          if (id.length > 0 && !id.startsWith(SYNTHETIC_ID_PREFIX)) {
            call.id = id;
          }
          parts.push(withSignature({ functionCall: call }, b));
        }
      }
      if (parts.length === 0) {
        parts.push({ text: ' ' });
      }
      out.push({ role: 'model', parts: parts });
      continue;
    }
    for (const b of m.content) {
      if (b.type === 'tool_result') {
        const id = b.tool_use_id ?? '';
        const result: Record<string, Object> = {};
        result[b.is_error ? 'error' : 'result'] = b.content ?? '';
        const resp: GmFunctionResponse = { name: toolNames[id] ?? '', response: result };
        if (id.length > 0 && !id.startsWith(SYNTHETIC_ID_PREFIX)) {
          resp.id = id;
        }
        parts.push({ functionResponse: resp });
      } else if (b.type === 'text' && b.text !== undefined) {
        parts.push({ text: b.text });
      }
    }
    if (parts.length > 0) {
      out.push({ role: 'user', parts: parts });
    }
  }
  return out;
}

/** effort level -> ThinkingLevel enum (Gemini 3 and later; the 2.5 models used a token budget instead) */
export const GEMINI_THINKING_LEVEL: Record<string, string> = {
  'minimal': 'MINIMAL', 'low': 'LOW', 'medium': 'MEDIUM', 'high': 'HIGH'
};

/** `effort` ("low", ...) becomes the thinking level; '' or an unknown level leaves the model's default. */
export function buildGeminiRequest(system: string, tools: ToolDef[], messages: ApiMessage[],
  effort: string = ''): GmRequest {
  const req: GmRequest = {
    systemInstruction: { parts: [{ text: system }] },
    contents: toGeminiContents(messages),
    tools: toGeminiTools(tools),
    toolConfig: { functionCallingConfig: { mode: 'AUTO' } }
  };
  const level = GEMINI_THINKING_LEVEL[effort];
  if (level !== undefined) {
    req.generationConfig = { thinkingConfig: { thinkingLevel: level } };
  }
  return req;
}

// ---------- responses ----------

/** Parses a 200 response into the agent's response format (exported for tests). */
export function parseGeminiResponse(body: string): MessagesResponse {
  let parsed: GmResponse;
  try {
    parsed = JSON.parse(body) as GmResponse;
  } catch (e) {
    throw new LlmError(200, 'invalid_response', 'Response is not valid JSON', true);
  }
  if (!parsed) {
    throw new LlmError(200, 'invalid_response', 'Empty response', true);
  }
  const id = parsed.responseId ?? '';
  const model = parsed.modelVersion ?? '';
  if (!Array.isArray(parsed.candidates) || parsed.candidates.length === 0) {
    if (parsed.promptFeedback && parsed.promptFeedback.blockReason) {
      return { id: id, model: model, stop_reason: 'refusal', content: [] };
    }
    throw new LlmError(200, 'invalid_response', 'Response has no candidates', true);
  }
  const cand = parsed.candidates[0];
  const parts = cand.content && Array.isArray(cand.content.parts) ? cand.content.parts : [];
  const content: ContentBlock[] = [];
  let calls = 0;
  for (let i = 0; i < parts.length; i++) {
    const p = parts[i];
    let block: ContentBlock | undefined = undefined;
    if (p.functionCall) {
      calls++;
      block = {
        type: 'tool_use',
        id: p.functionCall.id ?? `${SYNTHETIC_ID_PREFIX}${Date.now()}-${i}`,
        name: p.functionCall.name,
        input: p.functionCall.args ?? {}
      };
    } else if (p.thought === true) {
      block = { type: 'thinking', thinking: p.text ?? '' };
    } else if (p.text !== undefined) {
      block = { type: 'text', text: p.text };
    }
    if (block !== undefined) {
      if (p.thoughtSignature) {
        block.thought_signature = p.thoughtSignature;
      }
      content.push(block);
    }
  }
  const reason = cand.finishReason ?? 'STOP';
  let stop = 'end_turn';
  if (REFUSAL_REASONS.indexOf(reason) >= 0) {
    stop = 'refusal';
  } else if (reason === 'MAX_TOKENS') {
    stop = 'max_tokens';
  } else if (calls > 0) {
    stop = 'tool_use';
  }
  return { id: id, model: model, stop_reason: stop, content: content };
}

/** Maps a Gemini error response onto LlmError (exported for tests). */
export function parseGeminiError(status: number, body: string): LlmError {
  let message = `HTTP ${status}`;
  let gStatus = '';
  try {
    const parsed = JSON.parse(body) as GmErrorBody;
    if (parsed && parsed.error) {
      message = parsed.error.message ?? message;
      gStatus = parsed.error.status ?? '';
    }
  } catch (e) {
    if (body.length > 0) {
      message = `HTTP ${status}: ${body.substring(0, 200)}`;
    }
  }
  // An invalid key is reported as 400 INVALID_ARGUMENT "API key not valid..."
  if (gStatus === 'UNAUTHENTICATED' || (status === 400 && message.indexOf('API key') >= 0)) {
    return new LlmError(status, 'authentication_error', message, false);
  }
  return new LlmError(status, errorTypeForStatus(status), message, isRetryableStatus(status));
}

function handleResponse(resp: HttpResponse): MessagesResponse {
  if (resp.status >= 200 && resp.status < 300) {
    return parseGeminiResponse(resp.body);
  }
  throw parseGeminiError(resp.status, resp.body);
}

// ---------- client ----------

export class GeminiClient implements ChatClient {
  private apiKey: string;
  private model: string;
  private effort: string;

  constructor(apiKey: string, model: string, effort: string = '') {
    this.apiKey = apiKey;
    // accept "models/gemini-..." as well as "gemini-..."
    this.model = model.startsWith('models/') ? model.substring('models/'.length) : model;
    this.effort = effort;
  }

  createMessage(system: string, tools: ToolDef[], messages: ApiMessage[]): Promise<MessagesResponse> {
    const url = `${GEMINI_BASE}${encodeURIComponent(this.model)}:generateContent`;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'x-goog-api-key': this.apiKey
    };
    const body = JSON.stringify(buildGeminiRequest(system, tools, messages, this.effort));
    return postWithRetry<MessagesResponse>(url, headers, body, handleResponse);
  }
}
