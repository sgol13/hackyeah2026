import { DISPLAY_FONT } from '../common/Fonts';
import { Composer } from '../components/Composer';
import { OaMark } from '../components/OaMark';
import { KEY_OV_BUSY, KEY_OV_MODEL, KEY_OV_NOTICE, OverlayController } from '../overlay/OverlayController';

@Entry
@Component
struct OverlaySheet {
  @State task: string = '';
  @StorageProp(KEY_OV_NOTICE) notice: string = '';
  @StorageProp(KEY_OV_BUSY) busy: boolean = false;
  @StorageProp(KEY_OV_MODEL) model: string = '';

  build() {
    Column({ space: 14 }) {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.line'))
      Row({ space: 10 }) {
        OaMark({ markSize: 28, spinning: this.busy })
        Text('What should I do?')
          .fontFamily(DISPLAY_FONT)
          .fontSize(22)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      Composer({
        text: $task,
        running: false,
        canRun: !this.busy,
        onRun: () => {
          OverlayController.get().run(this.task);
        },
        onStop: () => {
        },
        onFocusChange: (focused: boolean) => {
          OverlayController.get().liftSheet(focused);
        }
      })
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Text(this.busy ? 'Starting…' : this.model)
        .fontSize(13)
        .fontColor($r('app.color.ink_muted'))
        .width('100%')
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 24 })
    .width('100%')
    .height('100%')
    .borderRadius({ topLeft: 28, topRight: 28 })
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 24, color: '#40000000', offsetY: -4 })
  }
}
