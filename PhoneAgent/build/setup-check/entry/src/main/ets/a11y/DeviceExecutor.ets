import { AccessibilityAction, AccessibilityElement, AccessibilityExtensionContext } from '@kit.AccessibilityKit';
import { bundleManager, launcherBundleManager, Want } from '@kit.AbilityKit';
import { process } from '@kit.ArkTS';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { Executor } from '../agent/AgentLoop';
import { serializeScreen, SerializedScreen } from '../agent/ScreenText';
import { OWN_BUNDLE } from '../common/Bridge';
import {
  clickElement,
  globalAction,
  readScreen,
  ScreenSnapshot,
  scrollElement,
  setElementText
} from './ScreenReader';

const MAX_SCREEN_ITEMS = 150;
const SETTLE_MS = 1200;
const FOCUS_MS = 400;
const UID_PER_USER = 200000;

interface AppEntry {
  label: string;
  bundleName: string;
  moduleName: string;
  abilityName: string;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/** Executes agent actions on the real device through the accessibility extension. */
export class DeviceExecutor implements Executor {
  private ctx: AccessibilityExtensionContext;
  private snapshot: ScreenSnapshot | undefined = undefined;
  private screen: SerializedScreen | undefined = undefined;
  private apps: AppEntry[] = [];

  constructor(ctx: AccessibilityExtensionContext) {
    this.ctx = ctx;
    this.loadApps().catch(() => {
      // labels are a nicety; launch_app loads the list again when needed
    });
  }

  appLabel(bundleName: string): string {
    const app = this.apps.find((a: AppEntry) => a.bundleName === bundleName);
    return app === undefined ? '' : app.label;
  }

  private async loadApps(): Promise<void> {
    if (this.apps.length > 0) {
      return;
    }
    // System API (GET_BUNDLE_INFO_PRIVILEGED)
    const userId = Math.floor(process.uid / UID_PER_USER);
    const infos = await launcherBundleManager.getAllLauncherAbilityInfo(userId);
    for (const info of infos) {
      const el = info.elementName;
      if (el.bundleName === OWN_BUNDLE) {
        continue;
      }
      const moduleName = el.moduleName ?? '';
      let label = el.bundleName;
      try {
        label = await bundleManager.getAbilityLabel(el.bundleName, moduleName, el.abilityName);
      } catch (e) {
        // keep bundle name as label
      }
      this.apps.push({ label: label, bundleName: el.bundleName, moduleName: moduleName, abilityName: el.abilityName });
    }
  }

  async listApps(): Promise<string> {
    await this.loadApps();
    return this.apps.map((a: AppEntry) => `${a.label} (${a.bundleName})`).join('\n');
  }

  async launchApp(bundleName: string): Promise<void> {
    await this.loadApps();
    const app = this.apps.find((a: AppEntry) => a.bundleName === bundleName);
    if (app === undefined) {
      throw new Error(`There is no launchable app "${bundleName}". Use a bundle name from the installed apps list.`);
    }
    const want: Want = { bundleName: app.bundleName, moduleName: app.moduleName, abilityName: app.abilityName };
    await this.ctx.startAbility(want);
  }

  async readScreen(): Promise<string> {
    const snap = await readScreen(this.ctx);
    const screen = serializeScreen(snap.nodes, MAX_SCREEN_ITEMS);
    this.snapshot = snap;
    this.screen = screen;
    return `App: ${snap.bundleName}\n${screen.text}`;
  }

  describeElement(index: number): string {
    if (this.screen === undefined || index < 0 || index >= this.screen.lines.length) {
      return '';
    }
    return this.screen.lines[index];
  }

  private rawIndex(index: number): number {
    if (this.snapshot === undefined || this.screen === undefined) {
      throw new Error('No screen has been read yet. Call read_screen first.');
    }
    const count = this.screen.indexMap.length;
    if (index < 0 || index >= count) {
      throw new Error(`Index ${index} is not on the current screen (valid indexes: 0-${count - 1}).`);
    }
    return this.screen.indexMap[index];
  }

  private element(index: number): AccessibilityElement {
    const snap = this.snapshot as ScreenSnapshot;
    return snap.elements[this.rawIndex(index)];
  }

  async click(index: number): Promise<void> {
    await clickElement(this.element(index));
  }

  async typeText(index: number, text: string): Promise<void> {
    const raw = this.rawIndex(index);
    const snap = this.snapshot as ScreenSnapshot;
    if (!snap.nodes[raw].editable) {
      throw new Error(`[${index}] is not an editable field (it has no "edit" flag).`);
    }
    const el = snap.elements[raw];
    // ArkUI text fields only accept SET_TEXT once focused.
    await clickElement(el);
    await sleep(FOCUS_MS);
    await setElementText(el, text);
  }

  async scroll(index: number, down: boolean): Promise<void> {
    await scrollElement(this.element(index), down);
  }

  async pressKey(key: string): Promise<void> {
    await globalAction(this.ctx, key === 'home' ? AccessibilityAction.HOME : AccessibilityAction.BACK);
  }

  async settle(): Promise<void> {
    await sleep(SETTLE_MS);
  }

  /**
   * One-time alarm through the system reminder service (the stock Clock app on Oniro has no alarms).
   * Reminders ring through our notifications, so they are switched on first (system API,
   * NOTIFICATION_CONTROLLER).
   */
  async setAlarm(hour: number, minute: number, label: string): Promise<string> {
    try {
      const bundle: notificationManager.BundleOption = { bundle: OWN_BUNDLE };
      if (!(await notificationManager.isNotificationEnabled(bundle))) {
        await notificationManager.setNotificationEnable(bundle, true);
      }
    } catch (e) {
      // publishReminder reports it if notifications are still off
    }
    const time = `${hour < 10 ? '0' : ''}${hour}:${minute < 10 ? '0' : ''}${minute}`;
    const alarm: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: hour,
      minute: minute,
      daysOfWeek: [],
      title: label.length > 0 ? label : 'Alarm',
      content: time,
      ringDuration: 60,
      snoozeTimes: 2,
      timeInterval: 5 * 60,
      actionButton: [
        { title: 'Close', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE },
        { title: 'Snooze', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_SNOOZE }
      ]
    };
    const id = await reminderAgentManager.publishReminder(alarm);
    return `Alarm set for ${time} in the system alarm service (reminder id ${id}). ` +
      'It rings once at the next occurrence of that time and shows a notification.';
  }
}
