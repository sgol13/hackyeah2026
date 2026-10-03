/**
 * LLM providers the agent can use. All of them plug into the same agent loop
 * through the Llm interface; each client translates the loop's conversation
 * format to its API. Anthropic is verified end to end on the device; OpenAI,
 * xAI and Gemini are implemented against their public API docs and unit-tested.
 */
import { AnthropicClient, ApiMessage, ChatClient, findModel, MessagesResponse } from './Anthropic';
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
}

export interface ProviderInfo {
  id: string;
  label: string;
  /** placeholder of the API key field */
  keyHint: string;
  /** suggested models; any other model ID can be entered as a custom model */
  models: ModelChoice[];
}

export const PROVIDERS: ProviderInfo[] = [
  {
    id: PROVIDER_ANTHROPIC, label: 'Anthropic Claude', keyHint: 'Anthropic API key (sk-ant-...)',
    models: [
      { id: 'claude-opus-5-5', label: 'Claude Opus 5.5' },
      { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5' },
      { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5' }
    ]
  },
  {
    id: PROVIDER_OPENAI, label: 'OpenAI', keyHint: 'OpenAI API key (sk-...)',
    models: [
      { id: 'gpt-5', label: 'GPT-5' },
      { id: 'gpt-5-mini', label: 'GPT-5 mini' }
    ]
  },
  {
    id: PROVIDER_XAI, label: 'xAI Grok', keyHint: 'xAI API key (xai-...)',
    models: [
      { id: 'grok-4', label: 'Grok 4' },
      { id: 'grok-3-mini', label: 'Grok 3 mini' }
    ]
  },
  {
    id: PROVIDER_GEMINI, label: 'Google Gemini', keyHint: 'Gemini API key (AIza...)',
    models: [
      { id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro' },
      { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash' }
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

class AnthropicLlm implements Llm {
  private client: AnthropicClient;

  constructor(client: AnthropicClient) {
    this.client = client;
  }

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    return this.client.createMessage(this.client.buildRequest(SYSTEM_PROMPT, TOOLS, messages));
  }
}

class ChatClientLlm implements Llm {
  private client: ChatClient;

  constructor(client: ChatClient) {
    this.client = client;
  }

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    return this.client.createMessage(SYSTEM_PROMPT, TOOLS, messages);
  }
}

/** Creates the model client for a provider; throws on an unknown provider or invalid model ID. */
export function createLlm(provider: string, apiKey: string, model: string): Llm {
  if (!isValidModelId(model)) {
    throw new Error(`Invalid model ID "${model}"`);
  }
  switch (provider) {
    case PROVIDER_ANTHROPIC:
      return new AnthropicLlm(new AnthropicClient(apiKey, findModel(model)));
    case PROVIDER_OPENAI:
      return new ChatClientLlm(new OpenAiCompatClient(OPENAI_CHAT_URL, apiKey, model));
    case PROVIDER_XAI:
      return new ChatClientLlm(new OpenAiCompatClient(XAI_CHAT_URL, apiKey, model));
    case PROVIDER_GEMINI:
      return new ChatClientLlm(new GeminiClient(apiKey, model));
    default:
      throw new Error(`Unknown AI provider "${provider}"`);
  }
}
