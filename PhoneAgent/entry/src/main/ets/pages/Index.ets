import { config } from '@kit.AccessibilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

const A11Y_ABILITY = 'com.hackyeah.phoneagent/AgentA11y';
const ERR_ALREADY_ENABLED = 9300002;

@Entry
@Component
struct Index {
  @State message: string = 'Enabling agent service...';

  aboutToAppear(): void {
    this.enableService();
  }

  private enableService(): void {
    // System API (WRITE_ACCESSIBILITY_CONFIG): turn on our own accessibility extension.
    config.enableAbility(A11Y_ABILITY, ['retrieve', 'gesture'])
      .then(() => {
        this.message = 'Agent service enabled';
      })
      .catch((err: BusinessError) => {
        this.message = err.code === ERR_ALREADY_ENABLED ? 'Agent service already enabled' :
          `enableAbility failed: ${err.code} ${err.message}`;
      });
  }

  build() {
    Column({ space: 16 }) {
      Text(this.message)
        .id('status')
        .fontSize(16)
      Button('Enable agent service')
        .onClick(() => this.enableService())
    }
    .padding(24)
    .height('100%')
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}
