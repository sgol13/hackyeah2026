/**
 * Minimal hand-written client for the Anthropic Messages API (POST /v1/messages).
 * There is no Anthropic SDK for ArkTS, so this speaks raw HTTP (see Http.ets).
 * Non-streaming; retries 429 / 5xx / 529 / network errors with backoff.
 *
 * The Messages API content blocks (text / tool_use / tool_result) are also the
 * provider-neutral conversation format of the agent loop; the OpenAI-compatible
 * and Gemini clients translate to and from it.
 */
import { HttpResponse, isRetryableStatus, LlmError, postWithRetry } from './Http';

const API_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';
// fallbacks: "default" re-runs a safety-declined request on Anthropic's recommended model.
const FALLBACK_BETA = 'server-side-fallback-2026-07-01';

// ---------- wire types (also the agent's conversation format) ----------

export interface ContentBlock {
  type: string;
  text?: string;
  id?: string;
  name?: string;
  input?: Record<string, Object>;
  tool_use_id?: string;
  content?: string;
  is_error?: boolean;
  thinking?: string;
  signature?: string;
  /** Gemini only: thought signature to send back with this part (never set for Anthropic) */
  thought_signature?: string;
}

export interface ApiMessage {
  role: string;
  content: ContentBlock[];
}

export interface JsonSchemaProperty {
  type: string;
  description?: string;
  enum?: string[];
}

export interface JsonSchema {
  type: string;
  properties: Record<string, JsonSchemaProperty>;
  required: string[];
  additionalProperties: boolean;
}

export interface ToolDef {
  name: string;
  description: string;
  input_schema: JsonSchema;
  strict?: boolean;
}

export interface ToolChoice {
  type: string;
}

export interface OutputConfig {
  effort: string;
}

export interface CacheControl {
  type: string;
}

export interface MessagesRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: ApiMessage[];
  tools: ToolDef[];
  tool_choice: ToolChoice;
  cache_control?: CacheControl;
  output_config?: OutputConfig;
  fallbacks?: string;
}

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens?: number;
}

export interface MessagesResponse {
  id: string;
  model: string;
  stop_reason: string;
  content: ContentBlock[];
  usage?: Usage;
}

/** A provider client that takes the agent's conversation format (OpenAI-compatible, Gemini). */
export interface ChatClient {
  createMessage(system: string, tools: ToolDef[], messages: ApiMessage[]): Promise<MessagesResponse>;
}

interface ApiErrorDetail {
  type: string;
  message: string;
}

interface ApiErrorBody {
  type: string;
  error?: ApiErrorDetail;
}

// ---------- models ----------

export interface ModelOption {
  id: string;
  label: string;
  /** output_config.effort; undefined = model does not take effort (Haiku 4.5, unknown models) */
  effort?: string;
  /** whether fallbacks:"default" is supported */
  fallbacks: boolean;
}

export const ANTHROPIC_MODELS: ModelOption[] = [
  { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', effort: 'medium', fallbacks: true },
  { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', effort: 'medium', fallbacks: true },
  { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', fallbacks: false }
];

/** Known model -> its options; any other (custom) model ID is sent as-is with no extra options. */
export function findModel(id: string): ModelOption {
  for (const m of ANTHROPIC_MODELS) {
    if (m.id === id) {
      return m;
    }
  }
  return { id: id, label: id, fallbacks: false };
}

// ---------- responses ----------

/** Turns a non-2xx HTTP response into an LlmError (exported for tests). */
export function parseApiError(status: number, body: string): LlmError {
  let errorType = 'http_error';
  let message = `HTTP ${status}`;
  try {
    const parsed = JSON.parse(body) as ApiErrorBody;
    if (parsed.error) {
      errorType = parsed.error.type;
      message = parsed.error.message;
    }
  } catch (e) {
    if (body.length > 0) {
      message = `HTTP ${status}: ${body.substring(0, 200)}`;
    }
  }
  return new LlmError(status, errorType, message, isRetryableStatus(status));
}

/** Parses and sanity-checks a 200 response body (exported for tests). */
export function parseMessagesResponse(body: string): MessagesResponse {
  let parsed: MessagesResponse;
  try {
    parsed = JSON.parse(body) as MessagesResponse;
  } catch (e) {
    throw new LlmError(200, 'invalid_response', 'Response is not valid JSON', true);
  }
  if (!parsed || !Array.isArray(parsed.content) || typeof parsed.stop_reason !== 'string') {
    throw new LlmError(200, 'invalid_response', 'Response is missing content/stop_reason', true);
  }
  return parsed;
}

function handleResponse(resp: HttpResponse): MessagesResponse {
  if (resp.status >= 200 && resp.status < 300) {
    return parseMessagesResponse(resp.body);
  }
  throw parseApiError(resp.status, resp.body);
}

// ---------- client ----------

export class AnthropicClient {
  private apiKey: string;
  private model: ModelOption;

  constructor(apiKey: string, model: ModelOption) {
    this.apiKey = apiKey;
    this.model = model;
  }

  buildRequest(system: string, tools: ToolDef[], messages: ApiMessage[]): MessagesRequest {
    const req: MessagesRequest = {
      model: this.model.id,
      max_tokens: 16000,
      system: system,
      messages: messages,
      tools: tools,
      tool_choice: { type: 'auto' },
      // automatic prompt caching: history is append-only, so each turn reuses the cached prefix
      cache_control: { type: 'ephemeral' }
    };
    if (this.model.effort) {
      req.output_config = { effort: this.model.effort };
    }
    if (this.model.fallbacks) {
      req.fallbacks = 'default';
    }
    return req;
  }

  createMessage(req: MessagesRequest): Promise<MessagesResponse> {
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'x-api-key': this.apiKey,
      'anthropic-version': API_VERSION
    };
    if (this.model.fallbacks) {
      headers['anthropic-beta'] = FALLBACK_BETA;
    }
    return postWithRetry<MessagesResponse>(API_URL, headers, JSON.stringify(req), handleResponse);
  }
}
