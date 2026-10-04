import { describe, expect, it } from '@ohos/hypium';
import { snapOrb } from '../../../main/ets/overlay/OrbGeometry';

export default function orbGeometryTest() {
  describe('OrbGeometry.snapOrb', () => {
    // 1080x2340 screen, 180 px orb, 24 px margin, 120 px status bar, 150 px navigation bar
    it('snaps to the nearer side edge', 0, () => {
      expect(snapOrb(100, 1000, 180, 1080, 2340, 24, 120, 150).x).assertEqual(24);
      expect(snapOrb(700, 1000, 180, 1080, 2340, 24, 120, 150).x).assertEqual(876);
    });

    it('keeps it below the status bar and above the navigation bar', 0, () => {
      expect(snapOrb(700, -400, 180, 1080, 2340, 24, 120, 150).y).assertEqual(144);
      expect(snapOrb(700, 5000, 180, 1080, 2340, 24, 120, 150).y).assertEqual(1986);
      expect(snapOrb(700, 1000, 180, 1080, 2340, 24, 120, 150).y).assertEqual(1000);
    });

    it('handles an orb dropped half off-screen', 0, () => {
      const p = snapOrb(-120, 1000, 180, 1080, 2340, 24, 120, 150);
      expect(p.x).assertEqual(24);
    });

    it('never goes above the top inset on a tiny screen', 0, () => {
      expect(snapOrb(0, 50, 180, 300, 300, 24, 120, 150).y).assertEqual(144);
    });
  });
}
