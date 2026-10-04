import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import BuildProfile from 'BuildProfile';
import { dateText } from '../common/EventTime';

interface DemoNote { id: string; title: string; body: string; }

export default class EntryAbility extends UIAbility {
  private stage: window.WindowStage | undefined = undefined;
  private preparation: Promise<void> = Promise.resolve();

  onCreate(want: Want): void { this.preparation = this.prepareDemo(want); }

  onNewWant(want: Want): void {
    this.preparation = this.prepareDemo(want);
    if (want.parameters?.['prepareDemo'] === true) {
      this.preparation.then(() => { this.stage?.loadContent('pages/Index'); });
    }
  }

  /** Explicit debug-only fixture setup; normal launches never create or overwrite notes. */
  private async prepareDemo(want: Want): Promise<void> {
    if (!BuildProfile.DEBUG || want.parameters?.['prepareDemo'] !== true) { return; }
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const day = dateText(tomorrow);
    const prefs = preferences.getPreferencesSync(this.context, { name: 'notes' });
    let notes: DemoNote[] = [];
    try {
      const parsed = JSON.parse(prefs.getSync('notes', '[]') as string) as DemoNote[];
      if (Array.isArray(parsed)) { notes = parsed; }
    } catch (error) { notes = []; }
    const note: DemoNote = {
      id: 'presentation-grandma-party', title: 'Grandma birthday party',
      body: `Grandma birthday party is on ${day} at 17:00 at her house. The party lasts one hour, until 18:00. ` +
        'Create a calendar event called Grandma birthday party. ' +
        `Remind me to buy a gift on ${day} at 10:00. Grandma is saved in Contacts as Grandma.`
    };
    prefs.putSync('notes', JSON.stringify([note, ...notes.filter((item: DemoNote) => item.id !== note.id)]));
    await prefs.flush();
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    this.stage = stage;
    this.preparation.then(() => stage.loadContent('pages/Index'));
  }
}
