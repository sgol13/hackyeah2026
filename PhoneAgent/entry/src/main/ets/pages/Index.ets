import { config } from '@kit.AccessibilityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { LOG_ACTION, LOG_DONE, LOG_ERROR, LOG_TASK } from '../agent/AgentLoop';
import { isValidModelId, ModelChoice, ProviderInfo, PROVIDERS } from '../agent/Providers';
import {
  AgentStatus,
  EVT_RUN,
  EVT_STATUS,
  EVT_STOP,
  EVT_SYNC,
  LogEntry,
  OWN_A11Y_ABILITY,
  publishEvent,
  RunRequest,
  subscribeEvents,
  unsubscribeEvents
} from '../common/Bridge';
import { loadApiKey, loadSettings, saveApiKey, saveSettings } from '../common/Settings';
import { KEY_INCOMING_AUTORUN, KEY_INCOMING_TASK } from '../entryability/EntryAbility';

const ERR_ALREADY_ENABLED = 9300002;
const AUTORUN_DELAY_MS = 1500;
const SERVICE_ACK_TIMEOUT_MS = 5000;
const SERVICE_PING_TIMEOUT_MS = 8000;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

const CUSTOM_MODEL_LABEL = 'Custom model ID…';

function providerIndexOf(id: string): number {
  const i = PROVIDERS.findIndex((p: ProviderInfo) => p.id === id);
  return i >= 0 ? i : 0;
}

function modelOptions(p: ProviderInfo): SelectOption[] {
  const options = p.models.map((m: ModelChoice) => {
    const o: SelectOption = { value: m.label };
    return o;
  });
  const custom: SelectOption = { value: CUSTOM_MODEL_LABEL };
  options.push(custom);
  return options;
}

@Entry
@Component
struct Index {
  @State providerIndex: number = 0;
  @State apiKey: string = '';
  /** index into the provider's models; models.length = custom model ID */
  @State modelIndex: number = 0;
  @State customModel: string = '';
  @State task: string = '';
  @State running: boolean = false;
  @State serviceReady: boolean = false;
  @State notice: string = '';
  @State entries: LogEntry[] = [];
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
  /** number of statuses received from the service (any status proves it is listening) */
  private statusesSeen: number = 0;
  private statusInstance: number = 0;
  private statusVersion: number = 0;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const settings = loadSettings(this.ctx(), false);
    this.providerIndex = providerIndexOf(settings.provider);
    this.apiKey = settings.apiKey;
    const models = PROVIDERS[this.providerIndex].models;
    const i = models.findIndex((m: ModelChoice) => m.id === settings.model);
    if (i >= 0) {
      this.modelIndex = i;
    } else {
      this.modelIndex = models.length;
      this.customModel = settings.model;
    }
    subscribeEvents([EVT_STATUS], (event: string, data: string) => this.onStatus(data))
      .then((sub: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = sub;
        return publishEvent(EVT_SYNC, '');
      })
      .catch(() => {
        this.notice = 'Could not connect to the agent service.';
      });
    this.enableService();
  }

  aboutToDisappear(): void {
    unsubscribeEvents(this.subscriber);
  }

  onPageShow(): void {
    publishEvent(EVT_SYNC, '').catch(() => {});
    const incoming = AppStorage.get<string>(KEY_INCOMING_TASK);
    if (incoming !== undefined && incoming.length > 0) {
      this.task = incoming;
      AppStorage.setOrCreate<string>(KEY_INCOMING_TASK, '');
      if (AppStorage.get<boolean>(KEY_INCOMING_AUTORUN) === true) {
        AppStorage.setOrCreate<boolean>(KEY_INCOMING_AUTORUN, false);
        setTimeout(() => this.run(), AUTORUN_DELAY_MS);
      }
    }
  }

  private enableService(): void {
    // System API (WRITE_ACCESSIBILITY_CONFIG): switch on our own accessibility extension.
    config.enableAbility(OWN_A11Y_ABILITY, ['retrieve', 'gesture'])
      .then(() => {
        this.serviceReady = true;
      })
      .catch((err: BusinessError) => {
        if (err.code === ERR_ALREADY_ENABLED) {
          this.serviceReady = true;
        } else {
          this.notice = `Agent service unavailable (${err.code}): ${err.message}`;
        }
      });
  }

  private onStatus(data: string): void {
    let status: AgentStatus;
    try {
      status = JSON.parse(data) as AgentStatus;
    } catch (e) {
      return;
    }
    this.statusesSeen++;
    if (status.instance === this.statusInstance && status.version <= this.statusVersion) {
      return; // stale or duplicate
    }
    this.statusInstance = status.instance;
    this.statusVersion = status.version;
    this.running = status.running;
    if (status.full) {
      this.entries = status.entries;
      return;
    }
    const lastSeq = this.entries.length > 0 ? this.entries[this.entries.length - 1].seq : 0;
    for (const e of status.entries) {
      if (e.seq > lastSeq || e.seq === 1) {
        if (e.seq === 1) {
          this.entries = [];
        }
        this.entries.push(e);
      }
    }
  }

  private provider(): ProviderInfo {
    return PROVIDERS[this.providerIndex];
  }

  private isCustomModel(): boolean {
    return this.modelIndex >= this.provider().models.length;
  }

  private selectedModel(): string {
    return this.isCustomModel() ? this.customModel.trim() : this.provider().models[this.modelIndex].id;
  }

  /** Keeps each provider's key: save the one being left, load the one being switched to. */
  private async switchProvider(index: number): Promise<void> {
    if (index === this.providerIndex) {
      return;
    }
    await saveApiKey(this.ctx(), this.provider().id, this.apiKey);
    this.providerIndex = index;
    this.apiKey = loadApiKey(this.ctx(), this.provider().id, false);
    this.modelIndex = 0;
    this.customModel = '';
  }

  private async run(): Promise<void> {
    const task = this.task.trim();
    const provider = this.provider();
    if (this.apiKey.trim().length === 0) {
      this.notice = `Enter your ${provider.label} API key first.`;
      return;
    }
    const model = this.selectedModel();
    if (!isValidModelId(model)) {
      this.notice = 'Enter a valid model ID (letters, digits, . _ - : /).';
      return;
    }
    if (task.length === 0) {
      this.notice = 'Describe what the agent should do.';
      return;
    }
    await saveSettings(this.ctx(), { provider: provider.id, model: model, apiKey: this.apiKey });
    this.notice = '';
    this.running = true;
    // Make sure the service is listening (e.g. right after boot it may still be connecting).
    if (!(await this.waitForService(SERVICE_PING_TIMEOUT_MS))) {
      this.notice = 'Starting the agent service…';
      await this.restartService();
      if (!(await this.waitForService(2 * SERVICE_PING_TIMEOUT_MS))) {
        this.running = false;
        this.notice = 'The agent service is not responding. Try again in a moment.';
        return;
      }
      this.notice = '';
    }
    this.entries = [];
    this.running = true; // the ping's status reply reset it
    const req: RunRequest = { task: task, provider: provider.id, model: model };
    const versionBefore = this.statusVersion;
    try {
      await publishEvent(EVT_RUN, JSON.stringify(req));
    } catch (e) {
      this.running = false;
      this.notice = 'Could not reach the agent service.';
      return;
    }
    // The service answers every RUN with a status; if none arrives it was not listening yet.
    setTimeout(() => {
      if (this.running && this.statusVersion === versionBefore) {
        this.running = false;
        this.notice = 'The agent service did not respond. It is being restarted, tap Run again in a moment.';
        this.restartService();
      }
    }, SERVICE_ACK_TIMEOUT_MS);
  }

  /** Pings the service with SYNC until it answers with a status, or the timeout passes. */
  private async waitForService(timeoutMs: number): Promise<boolean> {
    const before = this.statusesSeen;
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        await publishEvent(EVT_SYNC, '');
      } catch (e) {
        // keep trying until the deadline
      }
      for (let i = 0; i < 10 && Date.now() < deadline; i++) {
        await sleep(100);
        if (this.statusesSeen > before) {
          return true;
        }
      }
    }
    return false;
  }

  /** Reconnects a service process that is enabled but not listening (e.g. after it was killed). */
  private async restartService(): Promise<void> {
    this.serviceReady = false;
    try {
      await config.disableAbility(OWN_A11Y_ABILITY);
    } catch (e) {
      // not enabled: fine, enable below
    }
    this.enableService();
  }

  private entryColor(kind: string): ResourceColor {
    if (kind === LOG_ERROR) {
      return '#C62828';
    }
    if (kind === LOG_DONE) {
      return '#2E7D32';
    }
    if (kind === LOG_ACTION) {
      return '#1565C0';
    }
    return '#424242';
  }

  private entryPrefix(kind: string): string {
    if (kind === LOG_ERROR) {
      return '✖ ';
    }
    if (kind === LOG_DONE) {
      return '✔ ';
    }
    if (kind === LOG_ACTION) {
      return '▶ ';
    }
    if (kind === LOG_TASK) {
      return 'Task: ';
    }
    return '';
  }

  build() {
    Column({ space: 10 }) {
      Text('Phone Agent')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width('100%')
      Text(this.serviceReady ? 'Agent service: on' : 'Agent service: off')
        .fontSize(12)
        .fontColor(this.serviceReady ? '#2E7D32' : '#C62828')
        .width('100%')
        .onClick(() => this.enableService())
      Select(PROVIDERS.map((p: ProviderInfo) => {
        const o: SelectOption = { value: p.label };
        return o;
      }))
        .selected(this.providerIndex)
        .value(this.provider().label)
        .width('100%')
        .onSelect((index: number) => {
          this.switchProvider(index);
        })
      TextInput({ placeholder: this.provider().keyHint, text: this.apiKey })
        .type(InputType.Password)
        .onChange((v: string) => {
          this.apiKey = v;
        })
      Select(modelOptions(this.provider()))
        .selected(this.modelIndex)
        .value(this.isCustomModel() ? CUSTOM_MODEL_LABEL : this.provider().models[this.modelIndex].label)
        .width('100%')
        .onSelect((index: number) => {
          this.modelIndex = index;
        })
      if (this.isCustomModel()) {
        TextInput({ placeholder: 'Model ID, e.g. gpt-5.1', text: this.customModel })
          .onChange((v: string) => {
            this.customModel = v;
          })
      }
      TextArea({ placeholder: 'What should I do? e.g. "Text grandma that I will come to her birthday"', text: this.task })
        .height(90)
        .onChange((v: string) => {
          this.task = v;
        })
      Row({ space: 10 }) {
        Button(this.running ? 'Running…' : 'Run')
          .id('run')
          .layoutWeight(1)
          .enabled(!this.running && this.serviceReady)
          .onClick(() => this.run())
        Button('Stop')
          .layoutWeight(1)
          .type(ButtonType.Capsule)
          .backgroundColor('#757575')
          .enabled(this.running)
          .onClick(() => {
            publishEvent(EVT_STOP, '').catch(() => {
              this.notice = 'Could not reach the agent service.';
            });
          })
      }
      .width('100%')
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(13)
          .fontColor('#C62828')
          .width('100%')
      }
      List({ space: 6 }) {
        ForEach(this.entries, (e: LogEntry) => {
          ListItem() {
            Text(this.entryPrefix(e.kind) + e.text)
              .fontSize(13)
              .fontColor(this.entryColor(e.kind))
              .fontStyle(e.kind === 'thought' ? FontStyle.Italic : FontStyle.Normal)
              .width('100%')
          }
        }, (e: LogEntry) => e.seq.toString())
      }
      .layoutWeight(1)
      .width('100%')
    }
    .padding(16)
    .width('100%')
    .height('100%')
  }
}
