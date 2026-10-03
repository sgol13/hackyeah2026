/**
 * The assistant overlay: floating orb, task sheet, status pill and edge glow, each its own TYPE_FLOAT window.
 * Lives in the OverlayService process; the pages read its state from AppStorage and call it back.
 * Windows that only show status are not focusable, so the app being operated stays the active window
 * that the agent reads (getRootInActiveWindow).
 */
import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { findProvider, modelSummary } from '../agent/Providers';
import { AgentClient } from '../common/AgentClient';
import {
  EVT_STATUS,
  EVT_UI_VISIBLE,
  ORIGIN_OVERLAY,
  OWN_BUNDLE,
  RunRequest,
  subscribeEvents,
  unsubscribeEvents
} from '../common/Bridge';
import { registerFonts } from '../common/Fonts';
import { checkRun } from '../common/RunCheck';
import { loadSettings } from '../common/Settings';
import { StatusTracker } from '../common/StatusTracker';
import { buildTimeline, Step } from '../common/Timeline';
import { snapOrb } from './OrbGeometry';

const DOMAIN = 0x0A12;
const TAG = 'Overlay';

export const KEY_OV_IDLE = 'ov.idle';
export const KEY_OV_STEPS = 'ov.steps';
export const KEY_OV_RUNNING = 'ov.running';
export const KEY_OV_NOTICE = 'ov.notice';
export const KEY_OV_BUSY = 'ov.busy';
export const KEY_OV_EXPANDED = 'ov.expanded';
export const KEY_OV_MODEL = 'ov.model';

const ORB_VP = 64;
const MARGIN_VP = 8;
const TOP_INSET_VP = 40;
const BOTTOM_INSET_VP = 56;
const IDLE_MS = 3000;
const SHEET_H_VP = 300;
const PILL_W_VP = 360;
const PILL_H_VP = 64;
const PILL_EXPANDED_H_VP = 440;
const RESULT_MS = 4000;

function logError(what: string, e: Error): void {
  hilog.error(DOMAIN, TAG, '%{public}s: %{public}s', what, e.message ?? JSON.stringify(e));
}

export class OverlayController {
  private static instance: OverlayController | undefined = undefined;
  private ctx: common.ServiceExtensionContext | undefined = undefined;
  private orb: window.Window | undefined = undefined;
  private sheet: window.Window | undefined = undefined;
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
  private sheetY: number = 0;
  private resultTimer: number = -1;
  private ready: Promise<void> = Promise.resolve();

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
    this.ready = this.doStart(ctx, showOrb, appVisible);
    await this.ready;
  }

  private async doStart(ctx: common.ServiceExtensionContext, showOrb: boolean, appVisible: boolean): Promise<void> {
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

  /**
   * Floating windows get no keyboardHeightChange (nor IME panel events) on the emulator, so while the
   * sheet's input has focus the sheet moves out of the keyboard's area (the lower 45% of the screen).
   */
  liftSheet(up: boolean): void {
    const y = up ? Math.max(this.px(TOP_INSET_VP), Math.round(this.screenH * 0.55) - this.px(SHEET_H_VP)) : this.sheetY;
    this.sheet?.moveWindowTo(0, y);
  }

  shutdown(): void {
    for (const s of this.subs) {
      unsubscribeEvents(s);
    }
    this.subs = [];
    this.closeSheet();
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

  /** Orb visible when: the switch is on, our app is not in front, and no sheet or pill is showing. */
  protected orbWanted(): boolean {
    return this.showOrb && !this.appVisible && this.sheet === undefined && this.pill === undefined;
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
      this.hidePill(); // the app shows the log itself
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
    if (this.tracker.running && this.sheet === undefined && !this.appVisible) {
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

  openSheet(): void {
    this.ready.then(() => this.doOpenSheet())
      .catch((e: Error) => {
        logError('sheet', e);
      });
  }

  private async doOpenSheet(): Promise<void> {
    if (this.tracker.running) {
      await this.showPill();
      this.togglePill();
      return;
    }
    if (this.sheet !== undefined || this.ctx === undefined) {
      return;
    }
    const s = loadSettings(this.ctx, true);
    AppStorage.setOrCreate<string>(KEY_OV_MODEL, modelSummary(s.provider, s.model, s.effort));
    AppStorage.setOrCreate<string>(KEY_OV_NOTICE, '');
    AppStorage.setOrCreate<boolean>(KEY_OV_BUSY, false);
    const h = this.px(SHEET_H_VP);
    this.sheetY = this.screenH - h;
    this.sheet = await this.createWindow('oa.sheet', 'pages/OverlaySheet', this.screenW, h, 0, this.sheetY, true);
    this.sheet.on('touchOutside', () => this.closeSheet());
    this.sheet.on('keyboardHeightChange', (kh: number) => {
      this.sheet?.moveWindowTo(0, this.sheetY - kh);
    });
    await this.sheet.showWindow();
    await this.updateOrb();
  }

  closeSheet(): void {
    const s = this.sheet;
    this.sheet = undefined;
    s?.destroyWindow();
    this.updateOrb().catch(() => {
    });
  }

  async run(task: string): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    const s = loadSettings(this.ctx, true);
    const p = findProvider(s.provider);
    const problem = checkRun(p === undefined ? s.provider : p.label, s.apiKey, s.model, task);
    if (problem.length > 0) {
      AppStorage.setOrCreate<string>(KEY_OV_NOTICE, problem);
      return;
    }
    AppStorage.setOrCreate<string>(KEY_OV_NOTICE, '');
    AppStorage.setOrCreate<boolean>(KEY_OV_BUSY, true);
    const req: RunRequest = {
      task: task.trim(), provider: s.provider, model: s.model, effort: s.effort, origin: ORIGIN_OVERLAY
    };
    const msg = await this.client.run(req);
    AppStorage.setOrCreate<boolean>(KEY_OV_BUSY, false);
    if (msg.length > 0) {
      AppStorage.setOrCreate<string>(KEY_OV_NOTICE, msg); // the sheet stays open (Review Focus 4)
      return;
    }
    this.closeSheet();
    await this.showPill();
  }

  stop(): void {
    this.client.stop();
  }

  async showPill(): Promise<void> {
    if (this.pill === undefined) {
      const w = Math.min(this.screenW - this.px(32), this.px(PILL_W_VP));
      this.pill = await this.createWindow('oa.pill', 'pages/OverlayPill', w, this.px(PILL_H_VP),
        Math.round((this.screenW - w) / 2), this.px(TOP_INSET_VP), false);
    }
    AppStorage.setOrCreate<boolean>(KEY_OV_EXPANDED, false);
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
