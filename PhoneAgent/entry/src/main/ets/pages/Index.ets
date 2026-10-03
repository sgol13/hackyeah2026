import { config } from '@kit.AccessibilityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { MODELS, ModelOption } from '../agent/Anthropic';
import { LOG_ACTION, LOG_DONE, LOG_ERROR, LOG_TASK } from '../agent/AgentLoop';
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
import { loadSettings, saveSettings } from '../common/Settings';
import { KEY_INCOMING_AUTORUN, KEY_INCOMING_TASK } from '../entryability/EntryAbility';

const ERR_ALREADY_ENABLED = 9300002;
const AUTORUN_DELAY_MS = 1500;
const SERVICE_ACK_TIMEOUT_MS = 5000;

function modelIndexOf(id: string): number {
  const i = MODELS.findIndex((m: ModelOption) => m.id === id);
  return i >= 0 ? i : 0;
}

@Entry
@Component
struct Index {
  @State apiKey: string = '';
  @State modelIndex: number = 0;
  @State task: string = '';
  @State running: boolean = false;
  @State serviceReady: boolean = false;
  @State notice: string = '';
  @State entries: LogEntry[] = [];
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;
  private statusInstance: number = 0;
  private statusVersion: number = 0;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const settings = loadSettings(this.ctx(), false);
    this.apiKey = settings.apiKey;
    this.modelIndex = modelIndexOf(settings.model);
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

  private async run(): Promise<void> {
    const task = this.task.trim();
    if (this.apiKey.trim().length === 0) {
      this.notice = 'Enter your Anthropic API key first.';
      return;
    }
    if (task.length === 0) {
      this.notice = 'Describe what the agent should do.';
      return;
    }
    const model = MODELS[this.modelIndex].id;
    await saveSettings(this.ctx(), { apiKey: this.apiKey, model: model });
    this.notice = '';
    this.entries = [];
    this.running = true;
    const req: RunRequest = { task: task, model: model };
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

  /** Reconnects a service process that is enabled but not listening (e.g. after it was killed). */
  private restartService(): void {
    this.serviceReady = false;
    config.disableAbility(OWN_A11Y_ABILITY)
      .catch(() => {})
      .finally(() => this.enableService());
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
      TextInput({ placeholder: 'Anthropic API key (sk-ant-...)', text: this.apiKey })
        .type(InputType.Password)
        .onChange((v: string) => {
          this.apiKey = v;
        })
      Select(MODELS.map((m: ModelOption) => {
        const o: SelectOption = { value: m.label };
        return o;
      }))
        .selected(this.modelIndex)
        .value(MODELS[this.modelIndex].label)
        .width('100%')
        .onSelect((index: number) => {
          this.modelIndex = index;
        })
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
