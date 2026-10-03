/**
 * Oniro Agent service: an AccessibilityExtensionAbility that hosts the agent loop.
 * Runs in its own process and stays connected while other apps are in the
 * foreground, which is where the agent has to read and operate the UI.
 */
import { AccessibilityEvent, AccessibilityEventInfo, AccessibilityExtensionAbility } from '@kit.AccessibilityKit';
import { Want } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgentListener, AgentLoop, Llm, LOG_ERROR } from '../agent/AgentLoop';
import { createLlm, findProvider } from '../agent/Providers';
import {
  AgentStatus,
  EVT_RUN,
  EVT_STATUS,
  EVT_STOP,
  EVT_SYNC,
  LogEntry,
  ORIGIN_OVERLAY,
  OWN_BUNDLE,
  publishEvent,
  RunRequest,
  subscribeEvents,
  unsubscribeEvents
} from '../common/Bridge';
import { loadApiKey } from '../common/Settings';
import { DeviceExecutor } from './DeviceExecutor';
import { SCRIPT_PREFIX, ScriptedLlm } from './ScriptedLlm';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0A11;
const TAG = 'AgentA11y';
const MAX_LOG_TEXT = 600;
const RETURN_TO_UI_DELAY_MS = 3000;

class StatusPublisher implements AgentListener {
  private owner: AgentA11y;

  constructor(owner: AgentA11y) {
    this.owner = owner;
  }

  log(kind: string, text: string): void {
    this.owner.addLog(kind, text);
  }
}

export default class AgentA11y extends AccessibilityExtensionAbility {
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
  private subscribing: boolean = false;
  private loop: AgentLoop | undefined = undefined;
  private running: boolean = false;
  private entries: LogEntry[] = [];
  private seq: number = 0;
  private readonly instance: number = Date.now();
  private statusVersion: number = 0;
  /** statuses are published one after another so the UI receives them in order */
  private publishQueue: Promise<void> = Promise.resolve();

  // The framework calls either the API 20 callbacks (onAccessibilityConnect...) or, e.g. when it
  // restarts the service process, the older ones (onConnect...). Both lead to the same idempotent setup.
  onAccessibilityConnect(): void {
    this.connect('onAccessibilityConnect');
  }

  onConnect(): void {
    this.connect('onConnect');
  }

  onAccessibilityDisconnect(): void {
    this.disconnect();
  }

  onDisconnect(): void {
    this.disconnect();
  }

  onAccessibilityEventInfo(event: AccessibilityEventInfo): void {
    // The agent reads the UI on demand; individual events are not needed.
  }

  onAccessibilityEvent(event: AccessibilityEvent): void {
    // same as above, for the older callback set
  }

  private connect(via: string): void {
    hilog.info(DOMAIN, TAG, 'service connected (%{public}s)', via);
    if (this.subscriber !== undefined || this.subscribing) {
      return;
    }
    this.subscribing = true;
    subscribeEvents([EVT_RUN, EVT_STOP, EVT_SYNC], (event: string, data: string) => this.onEvent(event, data))
      .then((sub: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = sub;
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'subscribe failed: %{public}s', err.message);
      })
      .finally(() => {
        this.subscribing = false;
      });
  }

  private disconnect(): void {
    hilog.info(DOMAIN, TAG, 'service disconnected');
    this.loop?.stop();
    unsubscribeEvents(this.subscriber);
    this.subscriber = undefined;
  }

  addLog(kind: string, text: string): void {
    const clipped = text.length > MAX_LOG_TEXT ? text.substring(0, MAX_LOG_TEXT) + '…' : text;
    const entry: LogEntry = { seq: ++this.seq, kind: kind, text: clipped };
    this.entries.push(entry);
    hilog.info(DOMAIN, TAG, '[%{public}s] %{public}s', kind, clipped);
    this.publishStatus(false, [entry]);
  }

  private publishStatus(full: boolean, entries: LogEntry[]): void {
    const status: AgentStatus = {
      instance: this.instance,
      version: ++this.statusVersion,
      running: this.running,
      full: full,
      entries: entries
    };
    const data = JSON.stringify(status);
    this.publishQueue = this.publishQueue
      .then(() => publishEvent(EVT_STATUS, data))
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'publish failed: %{public}s', err.message);
      });
  }

  private onEvent(event: string, data: string): void {
    if (event === EVT_RUN) {
      this.startRun(data);
    } else if (event === EVT_STOP) {
      this.loop?.stop();
    } else if (event === EVT_SYNC) {
      this.publishStatus(true, this.entries);
    }
  }

  private async startRun(data: string): Promise<void> {
    if (this.running) {
      this.addLog(LOG_ERROR, 'A task is already running.');
      return;
    }
    let req: RunRequest;
    try {
      req = JSON.parse(data) as RunRequest;
    } catch (e) {
      this.addLog(LOG_ERROR, 'Malformed run request.');
      return;
    }
    if (typeof req.task !== 'string' || req.task.trim().length === 0) {
      this.addLog(LOG_ERROR, 'The task is empty.');
      return;
    }
    const task = req.task.trim();
    let llm: Llm;
    if (BuildProfile.DEBUG && task.startsWith(SCRIPT_PREFIX)) {
      llm = new ScriptedLlm(task.substring(SCRIPT_PREFIX.length));
    } else {
      const provider = findProvider(req.provider);
      if (provider === undefined) {
        this.addLog(LOG_ERROR, `Unknown AI provider "${req.provider}".`);
        return;
      }
      const apiKey = loadApiKey(this.context, provider.id, true);
      if (apiKey.length === 0) {
        this.addLog(LOG_ERROR, `No ${provider.label} API key set. Add it in Oniro Agent Settings.`);
        return;
      }
      try {
        llm = createLlm(provider.id, apiKey, typeof req.model === 'string' ? req.model.trim() : '',
          typeof req.effort === 'string' ? req.effort : '');
      } catch (e) {
        this.addLog(LOG_ERROR, (e as Error).message);
        return;
      }
    }
    this.entries = [];
    this.running = true;
    const loop = new AgentLoop(llm, new DeviceExecutor(this.context), new StatusPublisher(this));
    this.loop = loop;
    try {
      await loop.run(task);
    } catch (e) {
      this.addLog(LOG_ERROR, `Unexpected failure: ${(e as Error).message}`);
    } finally {
      this.running = false;
      this.loop = undefined;
      this.publishStatus(true, this.entries);
    }
    // Leave the result visible in the target app for a moment, then show the log.
    // Overlay runs show the result in the pill instead and leave the user where they are.
    if (req.origin !== ORIGIN_OVERLAY) {
      setTimeout(() => this.showUi(), RETURN_TO_UI_DELAY_MS);
    }
  }

  private showUi(): void {
    const want: Want = { bundleName: OWN_BUNDLE, abilityName: 'EntryAbility' };
    this.context.startAbility(want).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'could not reopen UI: %{public}s', err.message);
    });
  }
}
