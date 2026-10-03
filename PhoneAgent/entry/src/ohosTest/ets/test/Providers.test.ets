import { describe, expect, it } from '@ohos/hypium';
import {
  createLlm,
  findProvider,
  isValidModelId,
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
  });
}
