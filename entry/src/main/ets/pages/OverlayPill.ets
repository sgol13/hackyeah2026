import { LOG_ERROR } from '../agent/AgentLoop';
import { currentStepText, currentThoughtText, Step } from '../common/Timeline';
import { OaMark } from '../components/OaMark';
import { StepList } from '../components/StepList';
import { KEY_OV_EXPANDED, KEY_OV_RUNNING, KEY_OV_STEPS, OverlayController } from '../overlay/OverlayController';

/** Status at the top while the agent works: the current step and the model's latest thought; tap for all steps. */
@Entry
@Component
struct OverlayPill {
  @StorageProp(KEY_OV_STEPS) steps: Step[] = [];
  @StorageProp(KEY_OV_RUNNING) running: boolean = false;
  @StorageProp(KEY_OV_EXPANDED) expanded: boolean = false;

  private failed(): boolean {
    return this.steps.length > 0 && this.steps[this.steps.length - 1].kind === LOG_ERROR;
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        OaMark({ markSize: 28, spinning: this.running })
        Column({ space: 2 }) {
          Text(this.running ? (currentStepText(this.steps) || 'Starting…') : (currentStepText(this.steps) || 'Done'))
            .fontSize(15)
            .fontColor(this.failed() ? $r('app.color.danger') : $r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.running && currentThoughtText(this.steps).length > 0) {
            Text(currentThoughtText(this.steps))
              .fontSize(13)
              .fontColor($r('app.color.ink_muted'))
              .fontStyle(FontStyle.Italic)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.running) {
          Column() {
            Image($r('app.media.ic_stop')).width(18).height(18).fillColor($r('app.color.on_orb'))
          }
          .id('pillStop')
          .width(40)
          .height(40)
          .borderRadius(20)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.danger'))
          .accessibilityText('Stop')
          .onClick(() => OverlayController.get().stop())
        }
      }
      .height(56)
      .width('100%')
      .onClick(() => OverlayController.get().togglePill())
      if (this.expanded) {
        Column() {
          StepList({ steps: this.steps, running: this.running })
        }
        .layoutWeight(1)
        Button('Open app')
          .width('100%')
          .backgroundColor($r('app.color.bg'))
          .fontColor($r('app.color.ink'))
          .onClick(() => OverlayController.get().openApp())
      }
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .width('100%')
    .height('100%')
    .borderRadius(this.expanded ? 24 : 32)
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
  }
}
