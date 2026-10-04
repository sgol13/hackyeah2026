import { describe, expect, it } from '@ohos/hypium';
import { LogEntry } from '../../../main/ets/common/Bridge';
import { buildTimeline, currentStepText, currentThoughtText, STEP_THINKING } from '../../../main/ets/common/Timeline';

function e(seq: number, kind: string, text: string): LogEntry {
  return { seq: seq, kind: kind, text: text };
}

export default function timelineTest() {
  describe('Timeline', () => {
    it('attaches thoughts to the next step', 0, () => {
      const steps = buildTimeline([
        e(1, 'task', 'text grandma'), e(2, 'thought', 'Open Messages first.'),
        e(3, 'action', 'Open Messages'), e(4, 'action', 'Look at the screen'), e(5, 'done', 'Sent.')
      ]);
      expect(steps.length).assertEqual(4);
      expect(steps[1].thoughts.join('|')).assertEqual('Open Messages first.');
      expect(steps[2].thoughts.length).assertEqual(0);
      expect(steps[3].kind).assertEqual('done');
    });

    it('trailing thoughts become a Thinking step', 0, () => {
      const steps = buildTimeline([e(1, 'task', 't'), e(2, 'thought', 'Hmm.')]);
      expect(steps[1].kind).assertEqual('thought');
      expect(steps[1].text).assertEqual(STEP_THINKING);
      expect(steps[1].thoughts[0]).assertEqual('Hmm.');
    });

    it('currentStepText is the last step, on one line', 0, () => {
      const long = 'a\nb ' + 'x'.repeat(600);
      const steps = buildTimeline([e(1, 'task', 't'), e(2, 'action', long)]);
      const text = currentStepText(steps);
      expect(text.indexOf('\n')).assertEqual(-1);
      expect(text.length <= 120).assertTrue();
      expect(currentStepText([])).assertEqual('');
    });

    it('currentThoughtText is the latest thought, on one line', 0, () => {
      const steps = buildTimeline([
        e(1, 'task', 't'), e(2, 'thought', 'First\nidea.'), e(3, 'action', 'Open Messages'),
        e(4, 'thought', 'Now pick Babcia.'), e(5, 'action', 'Tap "Babcia"'), e(6, 'action', 'Tap "Send"')
      ]);
      expect(currentThoughtText(steps)).assertEqual('Now pick Babcia.');
      expect(currentThoughtText(buildTimeline([e(1, 'task', 't'), e(2, 'thought', 'a\nb')]))).assertEqual('a b');
      expect(currentThoughtText([])).assertEqual('');
    });
  });
}
