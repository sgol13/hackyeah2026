import { common, Want } from '@kit.AbilityKit';
import { effortLabel, effortsFor, isValidModelId, ModelChoice, ProviderInfo, PROVIDERS } from '../agent/Providers';
import { AgentClient } from '../common/AgentClient';
import { OWN_BUNDLE } from '../common/Bridge';
import { DISPLAY_FONT } from '../common/Fonts';
import {
  KEY_SERVICE_READY,
  loadApiKey,
  loadSettings,
  loadShowOrb,
  OVERLAY_ABILITY,
  saveApiKey,
  saveSettings,
  saveShowOrb
} from '../common/Settings';
import { StatusTracker } from '../common/StatusTracker';

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
struct Settings {
  @State providerIndex: number = 0;
  @State apiKey: string = '';
  /** index into the provider's models; models.length = custom model ID */
  @State modelIndex: number = 0;
  @State customModel: string = '';
  /** '' = the model's default */
  @State effort: string = '';
  @State showOrb: boolean = true;
  @State reconnecting: boolean = false;
  @State serviceNotice: string = '';
  @StorageLink(KEY_SERVICE_READY) serviceReady: boolean = false;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const settings = loadSettings(this.ctx(), false);
    this.providerIndex = providerIndexOf(settings.provider);
    this.apiKey = settings.apiKey;
    const models = this.provider().models;
    const i = models.findIndex((m: ModelChoice) => m.id === settings.model);
    if (i >= 0) {
      this.modelIndex = i;
    } else {
      this.modelIndex = models.length;
      this.customModel = settings.model;
    }
    this.effort = this.efforts().indexOf(settings.effort) >= 0 ? settings.effort : '';
    this.showOrb = loadShowOrb(this.ctx());
  }

  onPageHide(): void {
    this.save();
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

  /** effort levels of the selected model; [] hides the effort row */
  private efforts(): string[] {
    return effortsFor(this.provider().id, this.selectedModel());
  }

  private effortOptions(): SelectOption[] {
    return [''].concat(this.efforts()).map((e: string) => {
      const o: SelectOption = { value: effortLabel(e) };
      return o;
    });
  }

  /** A model switch keeps the effort only if the new model has the same level. */
  private selectModel(index: number): void {
    this.modelIndex = index;
    if (this.efforts().indexOf(this.effort) < 0) {
      this.effort = '';
    }
    this.save();
  }

  private save(): void {
    saveSettings(this.ctx(), {
      provider: this.provider().id, model: this.selectedModel(), apiKey: this.apiKey, effort: this.effort
    });
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
    this.effort = '';
    this.save();
  }

  private async setShowOrb(on: boolean): Promise<void> {
    this.showOrb = on;
    await saveShowOrb(this.ctx(), on);
    const want: Want = { bundleName: OWN_BUNDLE, abilityName: OVERLAY_ABILITY };
    try {
      if (on) {
        await this.ctx().startServiceExtensionAbility(want);
      } else {
        await this.ctx().stopServiceExtensionAbility(want);
      }
    } catch (e) {
      // the overlay service is optional; the switch still takes effect on the next app start
    }
  }

  private async reconnect(): Promise<void> {
    this.reconnecting = true;
    const msg = await new AgentClient(new StatusTracker()).restartService();
    this.reconnecting = false;
    this.serviceReady = msg.length === 0;
    this.serviceNotice = msg;
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.ink_muted'))
      .margin({ top: 24, bottom: 8, left: 4 })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.ink'))
          .padding(10)
          .width(44)
          .height(44)
          .accessibilityText('Back')
          .onClick(() => this.getUIContext().getRouter().back())
        Text('Settings')
          .fontFamily(DISPLAY_FONT)
          .fontSize(24)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .height(56)

      Scroll() {
        Column() {
          this.sectionTitle('AI model')
          Column({ space: 12 }) {
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
              .showPasswordIcon(true)
              .onChange((v: string) => {
                this.apiKey = v;
              })
              .onBlur(() => this.save())
            Select(modelOptions(this.provider()))
              .selected(this.modelIndex)
              .value(this.isCustomModel() ? CUSTOM_MODEL_LABEL : this.provider().models[this.modelIndex].label)
              .width('100%')
              .onSelect((index: number) => {
                this.selectModel(index);
              })
            if (this.efforts().length > 0) {
              Row({ space: 12 }) {
                Text('Effort')
                  .fontSize(16)
                  .fontColor($r('app.color.ink'))
                Select(this.effortOptions())
                  .selected(this.effort.length === 0 ? 0 : this.efforts().indexOf(this.effort) + 1)
                  .value(effortLabel(this.effort))
                  .layoutWeight(1)
                  .onSelect((index: number) => {
                    this.effort = index === 0 ? '' : this.efforts()[index - 1];
                    this.save();
                  })
              }
              .width('100%')
              Text('Higher effort thinks longer: slower and more expensive, better on tricky tasks.')
                .fontSize(13)
                .fontColor($r('app.color.ink_muted'))
                .width('100%')
            }
            if (this.isCustomModel()) {
              TextInput({ placeholder: 'Model ID, e.g. gpt-5.1', text: this.customModel })
                .onChange((v: string) => {
                  this.customModel = v;
                })
                .onBlur(() => this.save())
              if (this.customModel.trim().length > 0 && !isValidModelId(this.customModel.trim())) {
                Text('Use letters, digits and . _ - : / only.')
                  .fontSize(13)
                  .fontColor($r('app.color.danger'))
                  .width('100%')
              }
            }
            Text('Each provider keeps its own key. Keys stay on this phone and are only sent to that provider.')
              .fontSize(13)
              .fontColor($r('app.color.ink_muted'))
              .width('100%')
          }
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))

          this.sectionTitle('Floating button')
          Row() {
            Column({ space: 2 }) {
              Text('Minimize to a floating orb')
                .fontSize(16)
                .fontColor($r('app.color.ink'))
              Text('When you leave the app it shrinks into an orb; tap it to come back.')
                .fontSize(13)
                .fontColor($r('app.color.ink_muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.showOrb })
              .selectedColor($r('app.color.orb_violet'))
              .onChange((on: boolean) => {
                this.setShowOrb(on);
              })
          }
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))

          this.sectionTitle('Agent service')
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Circle()
                .width(10)
                .height(10)
                .fill(this.serviceReady ? $r('app.color.orb_teal') : $r('app.color.danger'))
              Text(this.serviceReady ? 'On: the agent can read and use other apps' : 'Off: the agent cannot use other apps')
                .fontSize(16)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
            }
            .width('100%')
            Button(this.reconnecting ? 'Reconnecting…' : 'Reconnect')
              .enabled(!this.reconnecting)
              .backgroundColor($r('app.color.bg'))
              .fontColor($r('app.color.ink'))
              .onClick(() => this.reconnect())
            if (this.serviceNotice.length > 0) {
              Text(this.serviceNotice)
                .fontSize(13)
                .fontColor($r('app.color.danger'))
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
