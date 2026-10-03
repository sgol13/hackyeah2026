import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { commonEventManager } from '@kit.BasicServicesKit';
import { findProvider, modelSummary, PROVIDERS } from '../agent/Providers';
import { AgentClient } from '../common/AgentClient';
import { EVT_STATUS, ORIGIN_APP, RunRequest, subscribeEvents, unsubscribeEvents } from '../common/Bridge';
import { DISPLAY_FONT } from '../common/Fonts';
import { checkRun } from '../common/RunCheck';
import { AgentSettings, KEY_SERVICE_READY, loadSettings } from '../common/Settings';
import { StatusTracker } from '../common/StatusTracker';
import { buildTimeline, Step } from '../common/Timeline';
import { Composer } from '../components/Composer';
import { OaMark } from '../components/OaMark';
import { StepList } from '../components/StepList';
import { KEY_INCOMING_AUTORUN, KEY_INCOMING_TASK } from '../entryability/EntryAbility';

const AUTORUN_DELAY_MS = 1500;
const SUGGESTIONS: string[] = [
  'Text Babcia that I will come to her birthday',
  'Turn on Wi-Fi',
  'Set an alarm for 7:00'
];

@Entry
@Component
struct Index {
  @State settings: AgentSettings = {
    provider: PROVIDERS[0].id, model: PROVIDERS[0].models[0].id, apiKey: '', effort: ''
  };
  @State task: string = '';
  @State running: boolean = false;
  @State starting: boolean = false;
  @StorageLink(KEY_SERVICE_READY) serviceReady: boolean = false;
  @State notice: string = '';
  @State steps: Step[] = [];
  private tracker: StatusTracker = new StatusTracker();
  private client: AgentClient = new AgentClient(this.tracker);
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    subscribeEvents([EVT_STATUS], (event: string, data: string) => this.onStatus(data))
      .then((sub: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = sub;
        this.client.sync();
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
    this.settings = loadSettings(this.ctx(), false);
    this.client.sync();
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
    this.client.enableService().then((msg: string) => {
      this.serviceReady = msg.length === 0;
      if (msg.length > 0) {
        this.notice = msg;
      }
    });
  }

  private onStatus(data: string): void {
    if (this.tracker.apply(data)) {
      this.steps = buildTimeline(this.tracker.entries);
      this.running = this.tracker.running;
    }
  }

  private providerLabel(): string {
    const p = findProvider(this.settings.provider);
    return p === undefined ? this.settings.provider : p.label;
  }

  private hasKey(): boolean {
    return this.settings.apiKey.trim().length > 0;
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' });
  }

  private async run(): Promise<void> {
    const problem = checkRun(this.providerLabel(), this.settings.apiKey, this.settings.model, this.task);
    if (problem.length > 0) {
      this.notice = problem;
      return;
    }
    this.notice = '';
    this.starting = true;
    this.running = true;
    this.steps = [];
    const req: RunRequest = {
      task: this.task.trim(), provider: this.settings.provider, model: this.settings.model,
      effort: this.settings.effort, origin: ORIGIN_APP
    };
    const msg = await this.client.run(req);
    this.starting = false;
    if (msg.length > 0) {
      this.running = false;
      this.notice = msg;
    }
  }

  private stop(): void {
    this.client.stop().then((msg: string) => {
      if (msg.length > 0) {
        this.notice = msg;
      }
    });
  }

  @Builder
  emptyState() {
    Column({ space: 20 }) {
      Text('What should I do?')
        .fontFamily(DISPLAY_FONT)
        .fontSize(34)
        .fontColor($r('app.color.ink'))
      if (!this.hasKey()) {
        Text('Add an API key to get started.')
          .fontSize(16)
          .fontColor($r('app.color.ink_muted'))
        Button('Open Settings')
          .backgroundColor($r('app.color.orb_violet'))
          .fontColor($r('app.color.on_orb'))
          .onClick(() => this.openSettings())
      } else {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          ForEach(SUGGESTIONS, (s: string) => {
            Text(s)
              .fontSize(15)
              .fontColor($r('app.color.ink'))
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(18)
              .border({ width: 1, color: $r('app.color.line') })
              .backgroundColor($r('app.color.surface'))
              .onClick(() => {
                this.task = s;
              })
          }, (s: string) => s)
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 48 })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        OaMark({ markSize: 32, spinning: this.running })
        Text('Oniro Agent')
          .fontFamily(DISPLAY_FONT)
          .fontSize(20)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Image($r('app.media.ic_settings'))
          .id('settings')
          .width(24)
          .height(24)
          .fillColor($r('app.color.ink'))
          .padding(10)
          .width(44)
          .height(44)
          .accessibilityText('Settings')
          .onClick(() => this.openSettings())
      }
      .width('100%')

      Column() {
        if (this.steps.length === 0) {
          this.emptyState()
        } else {
          StepList({ steps: this.steps, running: this.running })
        }
      }
      .layoutWeight(1)
      .width('100%')

      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Composer({
        text: $task,
        running: this.running,
        canRun: this.serviceReady && !this.starting,
        onRun: () => this.run(),
        onStop: () => this.stop()
      })
      Row({ space: 8 }) {
        Text(modelSummary(this.settings.provider, this.settings.model, this.settings.effort))
          .fontSize(13)
          .fontColor($r('app.color.ink_muted'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.line') })
          .onClick(() => this.openSettings())
        Blank()
        Circle()
          .width(8)
          .height(8)
          .fill(this.serviceReady ? $r('app.color.orb_teal') : $r('app.color.danger'))
        Text(this.serviceReady ? 'Agent service on' : 'Agent service off')
          .fontSize(13)
          .fontColor($r('app.color.ink_muted'))
          .onClick(() => this.enableService())
      }
      .width('100%')
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
