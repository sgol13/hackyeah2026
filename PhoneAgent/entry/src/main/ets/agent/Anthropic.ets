/**
 * Minimal hand-written client for the Anthropic Messages API (POST /v1/messages).
 * There is no Anthropic SDK for ArkTS, so this speaks raw HTTP via @kit.NetworkKit.
 * Non-streaming; retries 429 / 5xx / 529 / network errors with backoff.
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

const API_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';
// fallbacks: "default" re-runs a safety-declined request on Anthropic's recommended model.
const FALLBACK_BETA = 'server-side-fallback-2026-07-01';
const MAX_RETRIES = 3;
const CONNECT_TIMEOUT_MS = 30000;
const READ_TIMEOUT_MS = 180000;

// ---------- wire types ----------

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
  /** output_config.effort; undefined = model does not take effort (Haiku 4.5) */
  effort?: string;
  /** whether fallbacks:"default" is supported */
  fallbacks: boolean;
}

export const MODELS: ModelOption[] = [
  { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', effort: 'medium', fallbacks: true },
  { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', effort: 'medium', fallbacks: true },
  { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', fallbacks: false }
];

export function findModel(id: string): ModelOption {
  for (const m of MODELS) {
    if (m.id === id) {
      return m;
    }
  }
  return MODELS[0];
}

// ---------- errors ----------

export class AnthropicError extends Error {
  status: number;
  errorType: string;
  retryable: boolean;

  constructor(status: number, errorType: string, message: string, retryable: boolean) {
    super(message);
    this.name = 'AnthropicError';
    this.status = status;
    this.errorType = errorType;
    this.retryable = retryable;
  }
}

/** Turns a non-2xx HTTP response into an AnthropicError (exported for tests). */
export function parseApiError(status: number, body: string): AnthropicError {
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
  const retryable = status === 429 || status >= 500;
  return new AnthropicError(status, errorType, message, retryable);
}

/** Parses and sanity-checks a 200 response body (exported for tests). */
export function parseMessagesResponse(body: string): MessagesResponse {
  let parsed: MessagesResponse;
  try {
    parsed = JSON.parse(body) as MessagesResponse;
  } catch (e) {
    throw new AnthropicError(200, 'invalid_response', 'Response is not valid JSON', true);
  }
  if (!parsed || !Array.isArray(parsed.content) || typeof parsed.stop_reason !== 'string') {
    throw new AnthropicError(200, 'invalid_response', 'Response is missing content/stop_reason', true);
  }
  return parsed;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

function retryDelayMs(attempt: number, retryAfterHeader: string | undefined): number {
  if (retryAfterHeader) {
    const seconds = parseFloat(retryAfterHeader);
    if (!isNaN(seconds) && seconds >= 0) {
      return Math.min(seconds * 1000, 60000);
    }
  }
  return Math.min(1000 * Math.pow(2, attempt), 16000);
}

// ---------- client ----------

export class AnthropicClient {
  private apiKey: string;
  private model: ModelOption;
  /** retry-after header of the last failed response, if any */
  private lastRetryAfter: string | undefined = undefined;

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

  async createMessage(req: MessagesRequest): Promise<MessagesResponse> {
    const body = JSON.stringify(req);
    let lastError: AnthropicError = new AnthropicError(0, 'unknown', 'request not sent', true);
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      let retryAfter: string | undefined = undefined;
      try {
        return await this.postOnce(body);
      } catch (e) {
        if (e instanceof AnthropicError) {
          lastError = e;
          retryAfter = this.lastRetryAfter;
        } else {
          const err = e as BusinessError;
          // network-level failure (DNS, connect, timeout): retryable
          lastError = new AnthropicError(0, 'network_error', `Network error ${err.code}: ${err.message}`, true);
        }
      }
      if (!lastError.retryable || attempt === MAX_RETRIES) {
        break;
      }
      await sleep(retryDelayMs(attempt, retryAfter));
    }
    throw lastError;
  }

  private async postOnce(body: string): Promise<MessagesResponse> {
    this.lastRetryAfter = undefined;
    const headers: Record<string, string> = {
      'content-type': 'application/json',
      'x-api-key': this.apiKey,
      'anthropic-version': API_VERSION
    };
    if (this.model.fallbacks) {
      headers['anthropic-beta'] = FALLBACK_BETA;
    }
    const request = http.createHttp();
    try {
      const resp = await request.request(API_URL, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: READ_TIMEOUT_MS
      });
      const text = typeof resp.result === 'string' ? resp.result as string : '';
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        return parseMessagesResponse(text);
      }
      const respHeaders = resp.header as Record<string, string>;
      this.lastRetryAfter = respHeaders ? respHeaders['retry-after'] : undefined;
      throw parseApiError(resp.responseCode, text);
    } finally {
      request.destroy();
    }
  }
}
