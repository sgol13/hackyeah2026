/** Hosts the assistant overlay. Started by the app (orb switch on) or by SystemUI on long-press Home. */
import { ServiceExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OWN_BUNDLE, SYSTEMUI_BUNDLE } from '../common/Bridge';
import { loadShowOrb } from '../common/Settings';
import { OverlayController } from './OverlayController';

const CALLER_BUNDLE = 'ohos.aafwk.param.callerBundleName';

export default class OverlayService extends ServiceExtensionAbility {
  onCreate(want: Want): void {
    const fromApp = want.parameters?.['fromApp'] === true;
    OverlayController.get().start(this.context, loadShowOrb(this.context), fromApp)
      .catch((e: Error) => {
        hilog.error(0x0A12, 'Overlay', 'start failed: %{public}s', e.message);
      });
  }

  onRequest(want: Want, startId: number): void {
    const caller = want.parameters?.[CALLER_BUNDLE];
    if (want.parameters?.['invoke'] === true && (caller === SYSTEMUI_BUNDLE || caller === OWN_BUNDLE)) {
      OverlayController.get().openSheet();
    }
  }

  onDestroy(): void {
    OverlayController.get().shutdown();
  }
}
