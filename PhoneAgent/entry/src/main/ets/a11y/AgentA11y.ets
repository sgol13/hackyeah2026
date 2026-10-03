/**
 * Phone Agent service: an AccessibilityExtensionAbility that hosts the agent loop.
 * Runs in its own process and stays connected while other apps are in the
 * foreground, which is where the agent has to read and operate the UI.
 */
import { AccessibilityEventInfo, AccessibilityExtensionAbility } from '@kit.AccessibilityKit';
import { Want } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AnthropicClient, ApiMessage, findModel, MessagesResponse } from '../agent/Anthropic';
import { AgentListener, AgentLoop, Llm, LOG_ERROR } from '../agent/AgentLoop';
import { SYSTEM_PROMPT } from '../agent/Prompt';
import { TOOLS } from '../agent/Tools';
import {
  AgentStatus,
  EVT_RUN,
  EVT_STATUS,
  EVT_STOP,
  EVT_SYNC,
  LogEntry,
  OWN_BUNDLE,
  publishEvent,
  RunRequest,
  subscribeEvents,
  unsubscribeEvents
} from '../common/Bridge';
import { loadSettings } from '../common/Settings';
import { DeviceExecutor } from './DeviceExecutor';
import { SCRIPT_PREFIX, ScriptedLlm } from './ScriptedLlm';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0A11;
const TAG = 'AgentA11y';
const MAX_LOG_TEXT = 600;
const RETURN_TO_UI_DELAY_MS = 3000;

class ClaudeLlm implements Llm {
  private client: AnthropicClient;

  constructor(client: AnthropicClient) {
    this.client = client;
  }

  send(messages: ApiMessage[]): Promise<MessagesResponse> {
    return this.client.createMessage(this.client.buildRequest(SYSTEM_PROMPT, TOOLS, messages));
  }
}

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
  private loop: AgentLoop | undefined = undefined;
  private running: boolean = false;
  private entries: LogEntry[] = [];
  private seq: number = 0;
  private readonly instance: number = Date.now();
  private statusVersion: number = 0;
  /** statuses are published one after another so the UI receives them in order */
  private publishQueue: Promise<void> = Promise.resolve();

  onAccessibilityConnect(): void {
    hilog.info(DOMAIN, TAG, 'service connected');
    subscribeEvents([EVT_RUN, EVT_STOP, EVT_SYNC], (event: string, data: string) => this.onEvent(event, data))
      .then((sub: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = sub;
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'subscribe failed: %{public}s', err.message);
      });
  }

  onAccessibilityDisconnect(): void {
    hilog.info(DOMAIN, TAG, 'service disconnected');
    this.loop?.stop();
    unsubscribeEvents(this.subscriber);
    this.subscriber = undefined;
  }

  onAccessibilityEventInfo(event: AccessibilityEventInfo): void {
    // The agent reads the UI on demand; individual events are not needed.
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
      const settings = loadSettings(this.context, true);
      if (settings.apiKey.length === 0) {
        this.addLog(LOG_ERROR, 'No Anthropic API key set. Enter it in Phone Agent first.');
        return;
      }
      llm = new ClaudeLlm(new AnthropicClient(settings.apiKey, findModel(req.model)));
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
    setTimeout(() => this.showUi(), RETURN_TO_UI_DELAY_MS);
  }

  private showUi(): void {
    const want: Want = { bundleName: OWN_BUNDLE, abilityName: 'EntryAbility' };
    this.context.startAbility(want).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'could not reopen UI: %{public}s', err.message);
    });
  }
}
