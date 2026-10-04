/**
 * The assistant overlay, each part its own TYPE_FLOAT window:
 *  - orb: the app "minimized", like a chat head. Shown while the app is in the background and no
 *    task runs; tap it to open the app again.
 *  - pill: while a task runs, at the top: the current step and the model's latest thought; tap it for
 *    all steps, Stop and Open app. Shown instead of the orb, with the edge glow.
 * Lives in the OverlayService process; the pages read its state from AppStorage and call it back.
 * The pill and glow are not focusable, so the app being operated stays the active window that the
 * agent reads (getRootInActiveWindow).
 */
import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgentClient } from '../common/AgentClient';
import { EVT_STATUS, EVT_UI_VISIBLE, OWN_BUNDLE, subscribeEvents, unsubscribeEvents } from '../common/Bridge';
import { registerFonts } from '../common/Fonts';
import { StatusTracker } from '../common/StatusTracker';
import { buildTimeline, Step } from '../common/Timeline';
import { snapOrb } from './OrbGeometry';

const DOMAIN = 0x0A12;
const TAG = 'Overlay';

export const KEY_OV_IDLE = 'ov.idle';
export const KEY_OV_STEPS = 'ov.steps';
export const KEY_OV_RUNNING = 'ov.running';
export const KEY_OV_EXPANDED = 'ov.expanded';

const ORB_VP = 64;
const MARGIN_VP = 8;
const TOP_INSET_VP = 40;
const BOTTOM_INSET_VP = 56;
const IDLE_MS = 3000;
const PILL_W_VP = 360;
const PILL_H_VP = 76;
const PILL_EXPANDED_H_VP = 440;
const RESULT_MS = 4000;

function logError(what: string, e: Error): void {
  hilog.error(DOMAIN, TAG, '%{public}s: %{public}s', what, e.message ?? JSON.stringify(e));
}

export class OverlayController {
  private static instance: OverlayController | undefined = undefined;
  private ctx: common.ServiceExtensionContext | undefined = undefined;
  private orb: window.Window | undefined = undefined;
  private pill: window.Window | undefined = undefined;
  private glow: window.Window | undefined = undefined;
  private tracker: StatusTracker = new StatusTracker();
  client: AgentClient = new AgentClient(this.tracker);
  private subs: commonEventManager.CommonEventSubscriber[] = [];
  private showOrb: boolean = true;
  private appVisible: boolean = false;
  private wasRunning: boolean = false;
  private screenW: number = 0;
  private screenH: number = 0;
  private density: number = 1;
  private orbX: number = 0;
  private orbY: number = 0;
  private dragX: number = 0;
  private dragY: number = 0;
  private dragOrbX: number = 0;
  private dragOrbY: number = 0;
  private idleTimer: number = -1;
  private resultTimer: number = -1;

  static get(): OverlayController {
    if (OverlayController.instance === undefined) {
      OverlayController.instance = new OverlayController();
    }
    return OverlayController.instance;
  }

  px(vp: number): number {
    return Math.round(vp * this.density);
  }

  async start(ctx: common.ServiceExtensionContext, showOrb: boolean, appVisible: boolean): Promise<void> {
    if (this.ctx !== undefined) {
      return;
    }
    this.ctx = ctx;
    this.showOrb = showOrb;
    this.appVisible = appVisible;
    const d = display.getDefaultDisplaySync();
    this.screenW = d.width;
    this.screenH = d.height;
    this.density = d.densityPixels;
    this.orbX = this.screenW - this.px(ORB_VP) - this.px(MARGIN_VP);
    this.orbY = Math.round(this.screenH * 0.6);
    this.subs.push(await subscribeEvents([EVT_STATUS], (e: string, data: string) => this.onStatus(data)));
    this.subs.push(await subscribeEvents([EVT_UI_VISIBLE], (e: string, data: string) => this.onAppVisible(data === '1')));
    this.client.sync();
    await this.updateOrb();
  }

  shutdown(): void {
    for (const s of this.subs) {
      unsubscribeEvents(s);
    }
    this.subs = [];
    this.hidePill();
    this.orb?.destroyWindow();
    this.orb = undefined;
    this.ctx = undefined;
  }

  /** Creates a float window showing `page`, transparent outside the page's own shapes. */
  async createWindow(name: string, page: string, w: number, h: number, x: number, y: number,
    focusable: boolean): Promise<window.Window> {
    const config: window.Configuration = { name: name, windowType: window.WindowType.TYPE_FLOAT, ctx: this.ctx };
    const win = await window.createWindow(config);
    await win.setUIContent(page);
    win.setWindowBackgroundColor('#00000000');
    await win.setWindowFocusable(focusable);
    await win.resize(w, h);
    await win.moveWindowTo(x, y);
    registerFonts(win.getUIContext());
    return win;
  }

  /** The orb is the minimized app: switch on, app in the background, and no task running (the pill shows then). */
  protected orbWanted(): boolean {
    return this.showOrb && !this.appVisible && this.pill === undefined && !this.tracker.running;
  }

  async updateOrb(): Promise<void> {
    const want = this.orbWanted();
    if (want && this.orb === undefined) {
      this.orb = await this.createWindow('oa.orb', 'pages/OverlayOrb', this.px(ORB_VP), this.px(ORB_VP),
        this.orbX, this.orbY, false);
    }
    if (this.orb === undefined) {
      return;
    }
    if (want) {
      await this.orb.showWindow();
      this.wake();
    } else {
      // minimize() is not supported for TYPE_FLOAT windows on the emulator (801); hide() is the system API
      await this.orb.hide();
    }
  }

  private onAppVisible(visible: boolean): void {
    this.appVisible = visible;
    if (visible) {
      this.hidePill(); // the app shows the steps itself
    } else if (this.tracker.running) {
      // the agent just switched to the app it operates: show the pill right away, never the orb
      this.showPill().catch((e: Error) => {
        logError('pill', e);
      });
    }
    this.updateOrb().catch((e: Error) => {
      logError('orb', e);
    });
  }

  private onStatus(data: string): void {
    if (!this.tracker.apply(data)) {
      return;
    }
    AppStorage.setOrCreate<Step[]>(KEY_OV_STEPS, buildTimeline(this.tracker.entries));
    AppStorage.setOrCreate<boolean>(KEY_OV_RUNNING, this.tracker.running);
    if (this.tracker.running && !this.appVisible) {
      this.showPill().catch((e: Error) => {
        logError('pill', e);
      });
    }
    if (this.wasRunning && !this.tracker.running) {
      clearTimeout(this.resultTimer);
      this.resultTimer = setTimeout(() => {
        if (AppStorage.get<boolean>(KEY_OV_EXPANDED) !== true) {
          this.hidePill();
        }
      }, RESULT_MS);
    }
    this.wasRunning = this.tracker.running;
  }

  /** Full opacity now, fades back to idle after a few seconds. */
  wake(): void {
    AppStorage.setOrCreate<boolean>(KEY_OV_IDLE, false);
    clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      AppStorage.setOrCreate<boolean>(KEY_OV_IDLE, true);
    }, IDLE_MS);
  }

  orbDragStart(displayX: number, displayY: number): void {
    this.dragX = displayX;
    this.dragY = displayY;
    this.dragOrbX = this.orbX;
    this.dragOrbY = this.orbY;
    this.wake();
  }

  /** displayX/Y are in vp relative to the screen, so they stay valid while the window moves under the finger. */
  orbDragMove(displayX: number, displayY: number): void {
    this.orbX = this.dragOrbX + this.px(displayX - this.dragX);
    this.orbY = this.dragOrbY + this.px(displayY - this.dragY);
    this.orb?.moveWindowTo(this.orbX, this.orbY);
  }

  orbDragEnd(): void {
    const p = snapOrb(this.orbX, this.orbY, this.px(ORB_VP), this.screenW, this.screenH, this.px(MARGIN_VP),
      this.px(TOP_INSET_VP), this.px(BOTTOM_INSET_VP));
    this.orbX = p.x;
    this.orbY = p.y;
    this.orb?.moveWindowTo(p.x, p.y);
    this.wake();
  }

  stop(): void {
    this.client.stop();
  }

  async showPill(): Promise<void> {
    if (this.pill === undefined) {
      const w = Math.min(this.screenW - this.px(32), this.px(PILL_W_VP));
      this.pill = await this.createWindow('oa.pill', 'pages/OverlayPill', w, this.px(PILL_H_VP),
        Math.round((this.screenW - w) / 2), this.px(TOP_INSET_VP), false);
      AppStorage.setOrCreate<boolean>(KEY_OV_EXPANDED, false);
    }
    clearTimeout(this.resultTimer);
    await this.pill.showWindow();
    await this.showGlow();
    await this.updateOrb();
  }

  hidePill(): void {
    clearTimeout(this.resultTimer);
    const p = this.pill;
    this.pill = undefined;
    p?.destroyWindow();
    const g = this.glow;
    this.glow = undefined;
    g?.destroyWindow();
    this.updateOrb().catch(() => {
    });
  }

  togglePill(): void {
    if (this.pill === undefined) {
      return;
    }
    const expanded = AppStorage.get<boolean>(KEY_OV_EXPANDED) !== true;
    AppStorage.setOrCreate<boolean>(KEY_OV_EXPANDED, expanded);
    this.pill.resize(Math.min(this.screenW - this.px(32), this.px(PILL_W_VP)),
      this.px(expanded ? PILL_EXPANDED_H_VP : PILL_H_VP));
    if (!expanded && !this.tracker.running) {
      this.hidePill();
    }
  }

  /** Opens the app again (tap on the orb, or "Open app" in the pill). */
  openApp(): void {
    this.hidePill();
    this.ctx?.startAbility({ bundleName: OWN_BUNDLE, abilityName: 'EntryAbility' });
  }

  private async showGlow(): Promise<void> {
    if (this.glow !== undefined) {
      return;
    }
    this.glow = await this.createWindow('oa.glow', 'pages/OverlayGlow', this.screenW, this.screenH, 0, 0, false);
    await this.glow.setWindowTouchable(false);
    await this.glow.showWindow();
  }
}
