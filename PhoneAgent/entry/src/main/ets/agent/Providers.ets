/**
 * LLM providers the agent can use. All of them plug into the same agent loop
 * through the Llm interface; each client translates the loop's conversation
 * format to its API. Anthropic is verified end to end on the device; OpenAI,
 * xAI and Gemini are implemented against their public API docs and unit-tested.
 *
 * Suggested models and their reasoning-effort levels follow the providers' docs
 * (checked 2026-10-04). The OpenAI client uses Chat Completions with function
 * tools, so OpenAI models that only take tools through the Responses API
 * (GPT-6 Astra, GPT-6.1 Sol; GPT-6 Luna unless effort is "none") are not suggested.
 */
import { AnthropicClient, ApiMessage, ChatClient, findModel, MessagesResponse, ModelOption, ToolDef } from './Anthropic';
import { Llm } from './AgentLoop';
import { GeminiClient } from './Gemini';
import { OPENAI_CHAT_URL, OpenAiCompatClient, XAI_CHAT_URL } from './OpenAiCompat';
import { SYSTEM_PROMPT } from './Prompt';
import { TOOLS } from './Tools';

export const PROVIDER_ANTHROPIC = 'anthropic';
export const PROVIDER_OPENAI = 'openai';
export const PROVIDER_XAI = 'xai';
export const PROVIDER_GEMINI = 'gemini';

export interface ModelChoice {
  id: string;
  label: string;
  /** reasoning effort levels the model accepts, lowest first; [] = no effort setting */
  efforts: string[];
}

export interface ProviderInfo {
  id: string;
  label: string;
  /** placeholder of the API key field */
  keyHint: string;
  /** suggested models; any other model ID can be entered as a custom model */
  models: ModelChoice[];
}

const CLAUDE_EFFORTS: string[] = ['low', 'medium', 'high', 'xhigh', 'max'];
const GPT_EFFORTS: string[] = ['none', 'low', 'medium', 'high', 'xhigh'];
const GPT56_EFFORTS: string[] = ['none', 'low', 'medium', 'high', 'xhigh', 'max'];

export const PROVIDERS: ProviderInfo[] = [
  {
    id: PROVIDER_ANTHROPIC, label: 'Anthropic Claude', keyHint: 'Anthropic API key (sk-ant-...)',
    models: [
      { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', efforts: CLAUDE_EFFORTS },
      { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', efforts: CLAUDE_EFFORTS },
      { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5', efforts: [] }
    ]
  },
  {
    id: PROVIDER_OPENAI, label: 'OpenAI', keyHint: 'OpenAI API key (sk-...)',
    models: [
      { id: 'gpt-5.5', label: 'GPT-5.5', efforts: GPT_EFFORTS },
      { id: 'gpt-5.6-terra', label: 'GPT-5.6 Terra', efforts: GPT56_EFFORTS },
      { id: 'gpt-5.6-luna', label: 'GPT-5.6 Luna', efforts: GPT56_EFFORTS }
    ]
  },
  {
    id: PROVIDER_XAI, label: 'xAI Grok', keyHint: 'xAI API key (xai-...)',
    models: [
      { id: 'grok-4.7', label: 'Grok 4.7', efforts: ['low', 'medium', 'high', 'xhigh'] },
      { id: 'grok-4.3', label: 'Grok 4.3', efforts: [] }
    ]
  },
  {
    id: PROVIDER_GEMINI, label: 'Google Gemini', keyHint: 'Gemini API key (AIza...)',
    models: [
      { id: 'gemini-3.8-flash', label: 'Gemini 3.8 Flash', efforts: ['low', 'medium', 'high'] },
      { id: 'gemini-3.1-pro-preview', label: 'Gemini 3.1 Pro (preview)', efforts: ['low', 'medium', 'high'] },
      { id: 'gemini-3.5-flash-lite', label: 'Gemini 3.5 Flash-Lite', efforts: ['minimal', 'low', 'medium', 'high'] }
    ]
  }
];

export function findProvider(id: string): ProviderInfo | undefined {
  return PROVIDERS.find((p: ProviderInfo) => p.id === id);
}

/** Model IDs end up in URLs (Gemini), so only allow plain identifier characters. */
export function isValidModelId(id: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._:\/-]{0,99}$/.test(id);
}

/** Display label of a model: the suggested model's label, or the custom ID itself. */
export function modelLabel(providerId: string, modelId: string): string {
  const m = findProvider(providerId)?.models.find((c: ModelChoice) => c.id === modelId);
  return m === undefined ? modelId : m.label;
}

const EFFORT_LABELS: Record<string, string> = {
  'none': 'Off', 'minimal': 'Minimal', 'low': 'Low', 'medium': 'Medium', 'high': 'High', 'xhigh': 'Extra high', 'max': 'Max'
};

/** Effort levels of a suggested model; [] for models without one and for custom model IDs. */
export function effortsFor(providerId: string, modelId: string): string[] {
  const m = findProvider(providerId)?.models.find((c: ModelChoice) => c.id === modelId);
  return m === undefined ? [] : m.efforts;
}

/** '' (not set) shows as 'Default'. */
export function effortLabel(effort: string): string {
  return effort.length === 0 ? 'Default' : (EFFORT_LABELS[effort] ?? effort);
}

/** The Anthropic model options with the chosen effort; '' or an unsupported effort keeps the model's default. */
export function anthropicModelOption(modelId: string, effort: string): ModelOption {
  const base = findModel(modelId);
  const usable = base.effort !== undefined && effortsFor(PROVIDER_ANTHROPIC, modelId).indexOf(effort) >= 0;
  return { id: base.id, label: base.label, effort: usable ? effort : base.effort, fallbacks: base.fallbacks };
}

/** Model chip text: "Claude Opus 5.5, high effort", or just the model when the effort is the default. */
export function modelSummary(providerId: string, modelId: string, effort: string): string {
  const model = modelLabel(providerId, modelId);
  return effort.length > 0 ? `${model}, ${effortLabel(effort).toLowerCase()} effort` : model;
}

export class AnthropicLlm implements Llm {
  private client: AnthropicClient;
  private system: string;
  private tools: ToolDef[];

  constructor(client: AnthropicClient, system: string = SYSTEM_PROMPT, tools: ToolDef[] = TOOLS) {
    this.client = client;
    this.system = system;
    this.tools = tools;
  }

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    return this.client.createMessage(this.client.buildRequest(this.system, this.tools, messages));
  }
}

export class ChatClientLlm implements Llm {
  private client: ChatClient;
  private system: string;
  private tools: ToolDef[];

  constructor(client: ChatClient, system: string = SYSTEM_PROMPT, tools: ToolDef[] = TOOLS) {
    this.client = client;
    this.system = system;
    this.tools = tools;
  }

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    return this.client.createMessage(this.system, this.tools, messages);
  }
}

/**
 * Creates the model client for a provider; throws on an unknown provider or invalid model ID.
 * An effort the model does not list is ignored, so stale settings never cause a 400.
 */
export function createLlm(provider: string, apiKey: string, model: string, effort: string = '',
  system: string = SYSTEM_PROMPT, tools: ToolDef[] = TOOLS): Llm {
  if (!isValidModelId(model)) {
    throw new Error(`Invalid model ID "${model}"`);
  }
  const e = effortsFor(provider, model).indexOf(effort) >= 0 ? effort : '';
  switch (provider) {
    case PROVIDER_ANTHROPIC:
      return new AnthropicLlm(new AnthropicClient(apiKey, anthropicModelOption(model, e)), system, tools);
    case PROVIDER_OPENAI:
      return new ChatClientLlm(new OpenAiCompatClient(OPENAI_CHAT_URL, apiKey, model, e), system, tools);
    case PROVIDER_XAI:
      return new ChatClientLlm(new OpenAiCompatClient(XAI_CHAT_URL, apiKey, model, e), system, tools);
    case PROVIDER_GEMINI:
      return new ChatClientLlm(new GeminiClient(apiKey, model, e), system, tools);
    default:
      throw new Error(`Unknown AI provider "${provider}"`);
  }
}
