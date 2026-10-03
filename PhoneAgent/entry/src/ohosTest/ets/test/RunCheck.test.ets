import { describe, expect, it } from '@ohos/hypium';
import { checkRun } from '../../../main/ets/common/RunCheck';

export default function runCheckTest() {
  describe('RunCheck', () => {
    it('asks for the key first, in Settings', 0, () => {
      expect(checkRun('Anthropic Claude', '  ', 'claude-opus-5-5', 'x')).assertEqual('Add your Anthropic Claude API key in Settings.');
    });

    it('rejects invalid model IDs and empty tasks', 0, () => {
      expect(checkRun('OpenAI', 'k', 'bad id!', 'x')).assertContain('Settings');
      expect(checkRun('OpenAI', 'k', 'gpt-5', '   ')).assertEqual('Describe what the agent should do.');
    });

    it('returns empty when everything is set', 0, () => {
      expect(checkRun('OpenAI', 'k', 'gpt-5', 'Turn on Wi-Fi')).assertEqual('');
    });
  });
}
