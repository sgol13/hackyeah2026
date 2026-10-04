import { describe, expect, it } from '@ohos/hypium';
import { AnthropicClient, ApiMessage, ChatClient, MessagesRequest, MessagesResponse, ToolDef } from '../../../main/ets/agent/Anthropic';
import { SYSTEM_PROMPT } from '../../../main/ets/agent/Prompt';
import { TOOLS, toolsForSkills } from '../../../main/ets/agent/Tools';
import { UserSkill } from '../../../main/ets/agent/Skills';
import {
  anthropicModelOption,
  AnthropicLlm,
  ChatClientLlm,
  createLlm,
  effortLabel,
  effortsFor,
  findProvider,
  isValidModelId,
  modelLabel,
  modelSummary,
  PROVIDER_ANTHROPIC,
  PROVIDER_GEMINI,
  PROVIDER_OPENAI,
  PROVIDER_XAI,
  PROVIDERS
} from '../../../main/ets/agent/Providers';

class RecordingChatClient implements ChatClient {
  system: string = '';
  tools: ToolDef[] = [];
  createMessage(system: string, tools: ToolDef[], messages: ApiMessage[]): Promise<MessagesResponse> {
    this.system = system;
    this.tools = tools;
    const response: MessagesResponse = { id: 'test', model: 'test', stop_reason: 'end_turn', content: [] };
    return Promise.resolve(response);
  }
}

class RecordingAnthropicClient extends AnthropicClient {
  request: MessagesRequest | undefined = undefined;
  constructor() {
    super('test-key', anthropicModelOption('claude-haiku-4-5', ''));
  }
  createMessage(request: MessagesRequest): Promise<MessagesResponse> {
    this.request = request;
    const response: MessagesResponse = { id: 'test', model: 'test', stop_reason: 'end_turn', content: [] };
    return Promise.resolve(response);
  }
}

export default function providersTest() {
  describe('Providers', () => {
    it('passes a custom system prompt and skill tools to both provider adapters', 0, async () => {
      const skill: UserSkill = { id: '1', name: 'Calendar', description: 'Events', body: 'Instructions', enabled: true };
      const tools = toolsForSkills([skill]);
      const chat = new RecordingChatClient();
      await new ChatClientLlm(chat, 'CUSTOM SYSTEM', tools).send([]);
      expect(chat.system).assertEqual('CUSTOM SYSTEM');
      expect(chat.tools.some((tool: ToolDef) => tool.name === 'read_skill')).assertTrue();
      const anthropic = new RecordingAnthropicClient();
      await new AnthropicLlm(anthropic, 'CUSTOM SYSTEM', tools).send([]);
      expect(anthropic.request?.system).assertEqual('CUSTOM SYSTEM');
      expect(anthropic.request?.tools.some((tool: ToolDef) => tool.name === 'read_skill')).assertTrue();
      for (const provider of PROVIDERS) {
        expect(createLlm(provider.id, 'key', provider.models[0].id, '', 'CUSTOM SYSTEM', tools) !== undefined).assertTrue();
      }
    });

    it('keeps the original prompt and tools as the default', 0, async () => {
      const chat = new RecordingChatClient();
      await new ChatClientLlm(chat).send([]);
      expect(chat.system).assertEqual(SYSTEM_PROMPT);
      expect(chat.tools.length).assertEqual(TOOLS.length);
      const anthropic = new RecordingAnthropicClient();
      await new AnthropicLlm(anthropic).send([]);
      expect(anthropic.request?.system).assertEqual(SYSTEM_PROMPT);
      expect(anthropic.request?.tools.length).assertEqual(TOOLS.length);
    });

    it('lists the four providers with suggested models', 0, () => {
      expect(PROVIDERS.length).assertEqual(4);
      for (const id of [PROVIDER_ANTHROPIC, PROVIDER_OPENAI, PROVIDER_XAI, PROVIDER_GEMINI]) {
        const p = findProvider(id);
        expect(p !== undefined).assertTrue();
        expect((p?.models.length ?? 0) > 0).assertTrue();
      }
      expect(findProvider('acme')).assertUndefined();
    });

    it('creates a client for every provider', 0, () => {
      for (const p of PROVIDERS) {
        expect(createLlm(p.id, 'key', p.models[0].id) !== undefined).assertTrue();
      }
    });

    it('rejects unknown providers and unsafe model IDs', 0, () => {
      let unknown = '';
      try {
        createLlm('acme', 'key', 'model-1');
      } catch (e) {
        unknown = (e as Error).message;
      }
      expect(unknown).assertContain('Unknown AI provider');
      expect(isValidModelId('gemini-2.5-flash')).assertTrue();
      expect(isValidModelId('models/gemini-2.5-pro')).assertTrue();
      expect(isValidModelId('gpt-5.1')).assertTrue();
      expect(isValidModelId('')).assertFalse();
      expect(isValidModelId('x?key=1')).assertFalse();
      expect(isValidModelId('a b')).assertFalse();
      let invalid = '';
      try {
        createLlm(PROVIDER_GEMINI, 'key', 'x?key=1');
      } catch (e) {
        invalid = (e as Error).message;
      }
      expect(invalid).assertContain('Invalid model ID');
    });

    it('modelLabel shows the suggested label or the raw custom ID', 0, () => {
      expect(modelLabel('anthropic', 'claude-opus-5-5')).assertEqual('Claude Opus 5.5');
      expect(modelLabel('openai', 'gpt-5.1-custom')).assertEqual('gpt-5.1-custom');
      expect(modelLabel('nope', 'x')).assertEqual('x');
    });

    it('modelSummary adds the effort only when one is chosen', 0, () => {
      expect(modelSummary('anthropic', 'claude-opus-5-5', 'xhigh')).assertEqual('Claude Opus 5.5, extra high effort');
      expect(modelSummary('anthropic', 'claude-opus-5-5', '')).assertEqual('Claude Opus 5.5');
      expect(modelSummary('openai', 'my-custom-model', '')).assertEqual('my-custom-model');
    });

    it('lists effort levels only for models that take them', 0, () => {
      expect(effortsFor('anthropic', 'claude-opus-5-5').join(',')).assertEqual('low,medium,high,xhigh,max');
      expect(effortsFor('anthropic', 'claude-haiku-4-5').length).assertEqual(0);
      expect(effortsFor('xai', 'grok-4.3').length).assertEqual(0);
      expect(effortsFor('openai', 'my-custom-model').length).assertEqual(0);
      expect(effortLabel('xhigh')).assertEqual('Extra high');
      expect(effortLabel('')).assertEqual('Default');
    });

    it('anthropicModelOption keeps the default effort unless a valid one is chosen', 0, () => {
      expect(anthropicModelOption('claude-sonnet-5-5', '').effort).assertEqual('medium');
      expect(anthropicModelOption('claude-sonnet-5-5', 'max').effort).assertEqual('max');
      expect(anthropicModelOption('claude-haiku-4-5', 'high').effort).assertUndefined();
    });

    it('createLlm ignores an effort the model does not take', 0, () => {
      expect(createLlm('xai', 'key', 'grok-4.3', 'high') !== undefined).assertTrue();
      expect(createLlm('gemini', 'key', 'gemini-3.8-flash', 'none') !== undefined).assertTrue();
    });
  });
}
