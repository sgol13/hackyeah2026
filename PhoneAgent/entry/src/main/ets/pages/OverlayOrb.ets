import { OaMark } from '../components/OaMark';
import { KEY_OV_IDLE, OverlayController } from '../overlay/OverlayController';

@Entry
@Component
struct OverlayOrb {
  @StorageProp(KEY_OV_IDLE) idle: boolean = false;

  build() {
    Stack() {
      Stack() {
        OaMark({ markSize: 40, spinning: false })
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .backgroundColor($r('app.color.surface'))
      .shadow({ radius: 12, color: '#33000000', offsetY: 3 })
    }
    .width('100%')
    .height('100%')
    .opacity(this.idle ? 0.55 : 1)
    .accessibilityText('Open Oniro Agent')
    .gesture(GestureGroup(GestureMode.Exclusive,
      TapGesture().onAction(() => OverlayController.get().openSheet()),
      PanGesture({ distance: 4 })
        .onActionStart((e: GestureEvent) => {
          OverlayController.get().orbDragStart(e.fingerList[0].displayX, e.fingerList[0].displayY);
        })
        .onActionUpdate((e: GestureEvent) => {
          OverlayController.get().orbDragMove(e.fingerList[0].displayX, e.fingerList[0].displayY);
        })
        .onActionEnd(() => OverlayController.get().orbDragEnd())
    ))
  }
}
