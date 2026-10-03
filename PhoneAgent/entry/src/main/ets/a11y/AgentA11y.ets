import { AccessibilityAction, AccessibilityEventInfo, AccessibilityExtensionAbility } from '@kit.AccessibilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clickElement, globalAction, readScreen, setElementText } from './ScreenReader';
import { serializeScreen } from '../agent/ScreenText';

const DOMAIN = 0x0A11;
const TAG = 'AgentA11y';
/** Spike-only debug channel: hdc shell cem publish -e com.hackyeah.phoneagent.DEBUG -d "dump" */
const DEBUG_EVENT = 'com.hackyeah.phoneagent.DEBUG';

export default class AgentA11y extends AccessibilityExtensionAbility {
  private subscriber?: commonEventManager.CommonEventSubscriber;

  onAccessibilityConnect(): void {
    hilog.info(DOMAIN, TAG, 'onAccessibilityConnect');
    this.subscribeDebug();
  }

  onAccessibilityDisconnect(): void {
    hilog.info(DOMAIN, TAG, 'onAccessibilityDisconnect');
    if (this.subscriber) {
      commonEventManager.unsubscribe(this.subscriber);
      this.subscriber = undefined;
    }
  }

  onAccessibilityEventInfo(event: AccessibilityEventInfo): void {
  }

  private subscribeDebug(): void {
    if (this.subscriber) {
      return;
    }
    commonEventManager.createSubscriber({ events: [DEBUG_EVENT] })
      .then((sub: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = sub;
        commonEventManager.subscribe(sub, (err: BusinessError, data: commonEventManager.CommonEventData) => {
          if (err) {
            hilog.error(DOMAIN, TAG, 'debug event error %{public}d', err.code);
            return;
          }
          this.handleDebug(data.data ?? '');
        });
        hilog.info(DOMAIN, TAG, 'debug channel ready');
      })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'createSubscriber failed %{public}d %{public}s', err.code, err.message);
      });
  }

  private async handleDebug(cmd: string): Promise<void> {
    hilog.info(DOMAIN, TAG, 'cmd: %{public}s', cmd);
    try {
      const t0 = Date.now();
      const snap = await readScreen(this.context);
      const screen = serializeScreen(snap.nodes, 150);
      hilog.info(DOMAIN, TAG, 'read %{public}s: %{public}d raw nodes in %{public}d ms',
        snap.bundleName, snap.nodes.length, Date.now() - t0);
      const sep = cmd.indexOf(':');
      const verb = sep >= 0 ? cmd.substring(0, sep) : cmd;
      const arg = sep >= 0 ? cmd.substring(sep + 1) : '';
      if (verb === 'dump') {
        for (const line of screen.text.split('\n')) {
          hilog.info(DOMAIN, TAG, '%{public}s', line);
        }
      } else if (verb === 'click') {
        const i = screen.indexMap[parseInt(arg)];
        await clickElement(snap.elements[i]);
        hilog.info(DOMAIN, TAG, 'clicked [%{public}s]', arg);
      } else if (verb === 'type') {
        const sep2 = arg.indexOf(':');
        const i = screen.indexMap[parseInt(arg.substring(0, sep2))];
        await setElementText(snap.elements[i], arg.substring(sep2 + 1));
        hilog.info(DOMAIN, TAG, 'typed into [%{public}s]', arg);
      } else if (verb === 'back') {
        await globalAction(this.context, AccessibilityAction.BACK);
      } else if (verb === 'home') {
        await globalAction(this.context, AccessibilityAction.HOME);
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'cmd %{public}s failed: %{public}d %{public}s', cmd, err.code, err.message);
    }
  }
}
