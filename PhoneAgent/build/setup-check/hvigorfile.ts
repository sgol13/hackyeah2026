import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor, HvigorNode } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

/*
 * System-app signing for builds started from DevEco Studio.
 * scripts/sign.ps1 creates a local, git-ignored signing config (.signing/ide-signing.json:
 * keystore, system_core profile, encrypted passwords). If it exists it is injected here,
 * so hvigor itself produces entry-default-signed.hap and the IDE's Run button can install it.
 * Without it, builds stay unsigned and scripts/build.ps1 signs them.
 */
const IDE_SIGNING = path.resolve(__dirname, '.signing', 'ide-signing.json');
const SIGNING_NAME = 'phoneagent-system';

hvigor.getRootNode().afterNodeEvaluate((node: HvigorNode) => {
  if (!fs.existsSync(IDE_SIGNING)) {
    return;
  }
  const appContext = node.getContext('com.ohos.app');
  const buildProfile = appContext.getBuildProfileOpt();
  buildProfile.app.signingConfigs = [
    { name: SIGNING_NAME, type: 'OpenHarmony', material: JSON.parse(fs.readFileSync(IDE_SIGNING, 'utf-8')) }
  ];
  for (const product of buildProfile.app.products) {
    product.signingConfig = SIGNING_NAME;
  }
  appContext.setBuildProfileOpt(buildProfile);
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
