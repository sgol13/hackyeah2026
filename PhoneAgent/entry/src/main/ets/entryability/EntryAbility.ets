import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';

const DOMAIN = 0x0000;

/** Keys used to hand launch parameters to the Index page. */
export const KEY_INCOMING_TASK = 'incomingTask';
export const KEY_INCOMING_AUTORUN = 'incomingAutorun';

/**
 * Optional launch parameters: `task` prefills the task field.
 * `autorun` (debug builds only) also starts it, for scripted testing over hdc:
 *   aa start -b com.hackyeah.phoneagent -a EntryAbility --ps task "..." --pb autorun true
 */
function takeLaunchParams(want: Want): void {
  const params = want.parameters;
  if (params === undefined) {
    return;
  }
  const task = params['task'];
  if (typeof task === 'string') {
    AppStorage.setOrCreate<string>(KEY_INCOMING_TASK, task as string);
    AppStorage.setOrCreate<boolean>(KEY_INCOMING_AUTORUN, BuildProfile.DEBUG && params['autorun'] === true);
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    takeLaunchParams(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    takeLaunchParams(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
      }
    });
  }
}
