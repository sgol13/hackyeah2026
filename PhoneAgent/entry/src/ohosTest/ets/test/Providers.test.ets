import { describe, expect, it } from '@ohos/hypium';
import {
  anthropicModelOption,
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

export default function providersTest() {
  describe('Providers', () => {
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
