import { launcherBundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { process } from '@kit.ArkTS';

// OpenHarmony uid = userId * 200000 + appId
const UID_PER_USER = 200000;

@Entry
@Component
struct Index {
  @State message: string = 'Loading...';

  aboutToAppear(): void {
    // System API (GET_BUNDLE_INFO_PRIVILEGED): only works when signed as system app.
    const userId = Math.floor(process.uid / UID_PER_USER);
    launcherBundleManager.getAllLauncherAbilityInfo(userId)
      .then((infos: Array<launcherBundleManager.LauncherAbilityInfo>) => {
        const names = infos.map((i: launcherBundleManager.LauncherAbilityInfo) => i.elementName.bundleName);
        this.message = `Launcher apps: ${infos.length}\n${names.join('\n')}`;
      })
      .catch((err: BusinessError) => {
        this.message = `getAllLauncherAbilityInfo failed: ${err.code} ${err.message}`;
      });
  }

  build() {
    Scroll() {
      Text(this.message)
        .id('HelloWorld')
        .fontSize(14)
        .padding(16)
    }
    .height('100%')
    .width('100%')
  }
}
