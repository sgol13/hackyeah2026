import { describe, expect, it } from '@ohos/hypium';
import { deviceTimeContext } from '../../../main/ets/agent/DeviceTime';

export default function deviceTimeTest() {
  describe('DeviceTime', () => {
    it('resolves jutro using the local calendar across a year boundary', 0, () => {
      const context = deviceTimeContext(new Date(2026, 11, 31, 23, 59));
      expect(context.includes('2026-12-31 23:59')).assertTrue();
      expect(context.includes('Tomorrow (jutro) is 2027-01-01')).assertTrue();
    });

    it('handles leap days and pads local dates and times', 0, () => {
      const context = deviceTimeContext(new Date(2028, 1, 28, 7, 5));
      expect(context.includes('2028-02-28 07:05')).assertTrue();
      expect(context.includes('Tomorrow (jutro) is 2028-02-29')).assertTrue();
    });
  });
}
