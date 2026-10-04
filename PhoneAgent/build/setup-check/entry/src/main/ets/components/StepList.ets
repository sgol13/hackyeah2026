/** The agent's steps as a vertical timeline; the model's thoughts sit folded under each step. */
import { LOG_DONE, LOG_ERROR, LOG_TASK, LOG_THOUGHT } from '../agent/AgentLoop';
import { DISPLAY_FONT } from '../common/Fonts';
import { Step } from '../common/Timeline';

const STEP_PADDING: Padding = { top: 6, bottom: 6 };

@Component
struct StepRow {
  @Prop step: Step;
  @Prop current: boolean = false;
  @State open: boolean = false;

  @Builder
  marker() {
    if (this.step.kind === LOG_DONE) {
      Image($r('app.media.ic_check')).width(18).height(18).fillColor($r('app.color.orb_violet'))
    } else if (this.step.kind === LOG_ERROR) {
      Image($r('app.media.ic_alert')).width(18).height(18).fillColor($r('app.color.danger'))
    } else {
      Circle()
        .width(this.current ? 10 : 8)
        .height(this.current ? 10 : 8)
        .fill(this.current ? $r('app.color.orb_violet') : $r('app.color.ink_muted'))
    }
  }

  build() {
    if (this.step.kind === LOG_TASK) {
      Text(this.step.text)
        .fontFamily(DISPLAY_FONT)
        .fontSize(22)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ top: 8, bottom: 16 })
    } else {
      Row({ space: 12 }) {
        Column() {
          this.marker()
        }
        .width(18)
        .height(24)
        .justifyContent(FlexAlign.Center)
        Column({ space: 4 }) {
          Text(this.step.text)
            .fontSize(this.step.kind === LOG_DONE ? 17 : 16)
            .fontWeight(this.step.kind === LOG_DONE ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.step.kind === LOG_ERROR ? $r('app.color.danger') : $r('app.color.ink'))
            .fontStyle(this.step.kind === LOG_THOUGHT ? FontStyle.Italic : FontStyle.Normal)
          if (this.step.thoughts.length > 0) {
            Text(this.step.thoughts.join(' '))
              .fontSize(14)
              .fontColor($r('app.color.ink_muted'))
              .maxLines(this.open ? 40 : 2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.open = !this.open;
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .padding(this.step.kind === LOG_DONE ? 14 : STEP_PADDING)
      .borderRadius(this.step.kind === LOG_DONE ? 18 : 0)
      .backgroundColor(this.step.kind === LOG_DONE ? $r('app.color.surface') : Color.Transparent)
    }
  }
}

@Component
export struct StepList {
  @Prop @Watch('scrollDown') steps: Step[] = [];
  @Prop running: boolean = false;
  private scroller: Scroller = new Scroller();

  scrollDown(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  build() {
    List({ scroller: this.scroller, space: 2 }) {
      ForEach(this.steps, (s: Step, i: number) => {
        ListItem() {
          StepRow({ step: s, current: this.running && i === this.steps.length - 1 })
        }
      }, (s: Step) => `${s.seq}-${s.kind}-${s.thoughts.length}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
