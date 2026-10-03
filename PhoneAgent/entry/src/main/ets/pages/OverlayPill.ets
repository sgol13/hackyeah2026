import { LOG_ERROR } from '../agent/AgentLoop';
import { currentStepText, Step } from '../common/Timeline';
import { OaMark } from '../components/OaMark';
import { StepList } from '../components/StepList';
import { KEY_OV_EXPANDED, KEY_OV_RUNNING, KEY_OV_STEPS, OverlayController } from '../overlay/OverlayController';

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
        Text(this.running ? currentStepText(this.steps) : (currentStepText(this.steps) || 'Done'))
          .fontSize(15)
          .fontColor(this.failed() ? $r('app.color.danger') : $r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .height(40)
      .width('100%')
      .onClick(() => OverlayController.get().togglePill())
      if (this.expanded) {
        Column() {
          StepList({ steps: this.steps, running: this.running })
        }
        .layoutWeight(1)
        Row({ space: 8 }) {
          Button('Open app')
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg'))
            .fontColor($r('app.color.ink'))
            .onClick(() => OverlayController.get().openApp())
          if (this.running) {
            Button('Stop')
              .layoutWeight(1)
              .backgroundColor($r('app.color.danger'))
              .fontColor($r('app.color.on_orb'))
              .onClick(() => OverlayController.get().stop())
          }
        }
        .width('100%')
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
