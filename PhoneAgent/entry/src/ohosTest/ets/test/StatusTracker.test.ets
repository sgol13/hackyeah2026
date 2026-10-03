import { describe, expect, it } from '@ohos/hypium';
import { AgentStatus, LogEntry } from '../../../main/ets/common/Bridge';
import { StatusTracker } from '../../../main/ets/common/StatusTracker';

function status(instance: number, version: number, full: boolean, entries: LogEntry[], running: boolean): string {
  const s: AgentStatus = { instance: instance, version: version, running: running, full: full, entries: entries };
  return JSON.stringify(s);
}

function e(seq: number, text: string): LogEntry {
  return { seq: seq, kind: 'action', text: text };
}

export default function statusTrackerTest() {
  describe('StatusTracker', () => {
    it('appends new entries and replaces on a full status', 0, () => {
      const t = new StatusTracker();
      expect(t.apply(status(1, 1, false, [e(1, 'a')], true))).assertTrue();
      expect(t.apply(status(1, 2, false, [e(2, 'b')], true))).assertTrue();
      expect(t.entries.length).assertEqual(2);
      expect(t.running).assertTrue();
      expect(t.apply(status(1, 3, true, [e(1, 'x')], false))).assertTrue();
      expect(t.entries.length).assertEqual(1);
      expect(t.running).assertFalse();
    });

    it('drops stale and duplicate statuses but still counts them as seen', 0, () => {
      const t = new StatusTracker();
      t.apply(status(1, 5, false, [e(1, 'a')], true));
      expect(t.apply(status(1, 5, false, [e(2, 'dup')], true))).assertFalse();
      expect(t.apply(status(1, 4, false, [e(2, 'old')], true))).assertFalse();
      expect(t.entries.length).assertEqual(1);
      expect(t.seen).assertEqual(3);
    });

    it('seq 1 starts a new log; a new service instance is accepted at any version', 0, () => {
      const t = new StatusTracker();
      t.apply(status(1, 1, false, [e(1, 'a'), e(2, 'b')], true));
      t.apply(status(1, 2, false, [e(1, 'new task')], true));
      expect(t.entries.length).assertEqual(1);
      expect(t.apply(status(2, 1, false, [e(2, 'c')], true))).assertTrue();
      expect(t.entries.length).assertEqual(2);
    });

    it('ignores unparsable payloads', 0, () => {
      const t = new StatusTracker();
      expect(t.apply('not json')).assertFalse();
      expect(t.seen).assertEqual(0);
    });
  });
}
