/** Hosts the assistant overlay (the orb the app minimizes to, and the status pill). Started by the app. */
import { ServiceExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadShowOrb } from '../common/Settings';
import { OverlayController } from './OverlayController';

export default class OverlayService extends ServiceExtensionAbility {
  onCreate(want: Want): void {
    const fromApp = want.parameters?.['fromApp'] === true;
    OverlayController.get().start(this.context, loadShowOrb(this.context), fromApp)
      .catch((e: Error) => {
        hilog.error(0x0A12, 'Overlay', 'start failed: %{public}s', e.message);
      });
  }

  onDestroy(): void {
    OverlayController.get().shutdown();
  }
}
