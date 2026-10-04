import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

interface Note { id: string; title: string; body: string; }

@Entry
@Component
struct Index {
  @State notes: Note[] = [];
  @State selected: Note | undefined = undefined;
  @State editing: boolean = false;
  @State title: string = '';
  @State body: string = '';
  @State busy: boolean = false;
  @State notice: string = '';
  private store: preferences.Preferences | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.store = preferences.getPreferencesSync(this.getUIContext().getHostContext() as common.UIAbilityContext,
        { name: 'notes' });
      const rows = JSON.parse(this.store.getSync('notes', '[]') as string) as Note[];
      this.notes = Array.isArray(rows) ? rows.filter((note: Note) => note !== null &&
        typeof note.id === 'string' && typeof note.title === 'string' && typeof note.body === 'string') : [];
    } catch (error) { this.notice = 'Could not load notes.'; }
  }

  private edit(note?: Note): void {
    this.selected = note; this.title = note?.title ?? ''; this.body = note?.body ?? '';
    this.notice = ''; this.editing = true;
  }

  private async persist(notes: Note[]): Promise<void> {
    if (this.store === undefined) { throw new Error('Notes storage is unavailable.'); }
    this.store.putSync('notes', JSON.stringify(notes));
    await this.store.flush(); this.notes = notes;
  }

  private async save(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      if (this.title.trim().length === 0 || this.title.length > 120 || this.body.length > 4000) {
        throw new Error('Enter a title (up to 120 characters) and a body of up to 4000 characters.');
      }
      const note: Note = { id: this.selected?.id ?? `${Date.now()}`, title: this.title.trim(), body: this.body };
      await this.persist([note, ...this.notes.filter((item: Note) => item.id !== note.id)]);
      this.selected = note; this.editing = false; this.notice = 'Note saved.';
    } catch (error) { this.notice = (error as Error).message; }
    finally { this.busy = false; }
  }

  private remove(): void {
    const note = this.selected;
    if (note === undefined || this.busy) { return; }
    AlertDialog.show({ title: 'Delete note?', message: `Delete "${note.title}"?`,
      primaryButton: { value: 'Cancel', action: () => {} },
      secondaryButton: { value: 'Delete', action: () => {
        this.busy = true;
        this.persist(this.notes.filter((item: Note) => item.id !== note.id)).then(() => {
          this.selected = undefined; this.notice = 'Note deleted.';
        }).catch((error: Error) => { this.notice = error.message; }).finally(() => { this.busy = false; });
      } } });
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text(this.editing ? 'Edit note' : 'Notes').fontSize(28).fontWeight(FontWeight.Bold).layoutWeight(1)
        if (this.editing || this.selected !== undefined) {
          Button('Back').id('notes_back').onClick(() => { this.editing = false; this.selected = undefined; this.notice = ''; })
            .enabled(!this.busy)
        } else { Button('New note').id('new_note').onClick(() => this.edit()).enabled(!this.busy) }
      }.width('100%')
      if (this.notice.length > 0) { Text(this.notice).width('100%').fontSize(14) }
      if (this.editing) {
        Scroll() {
          Column({ space: 12 }) {
            Text('Title').width('100%')
            TextInput({ text: this.title, placeholder: 'Note title' }).id('note_title').accessibilityText('Note title')
              .onChange((value: string) => { this.title = value; })
            Text('Body').width('100%')
            TextArea({ text: this.body, placeholder: 'Note text' }).id('note_body').accessibilityText('Note body')
              .height(280).onChange((value: string) => { this.body = value; })
            Button('Save note').id('save_note').width('100%').enabled(!this.busy).onClick(() => { this.save(); })
          }.width('100%')
        }.layoutWeight(1).width('100%').align(Alignment.Top)
      } else if (this.selected !== undefined) {
        Scroll() {
          Column({ space: 16 }) {
            Text(this.selected.title).id('note_heading').fontSize(24).fontWeight(FontWeight.Bold).width('100%')
            Text(this.selected.body).id('note_content').fontSize(18).width('100%')
            Row({ space: 12 }) {
              Button('Edit note').onClick(() => this.edit(this.selected)).enabled(!this.busy)
              Button('Delete note').onClick(() => this.remove()).enabled(!this.busy)
            }
          }.width('100%')
        }.layoutWeight(1).width('100%').align(Alignment.Top)
      } else {
        List({ space: 12 }) {
          if (this.notes.length === 0) { ListItem() { Text('No notes yet. Tap New note to add one.') } }
          ForEach(this.notes, (note: Note) => {
            ListItem() {
              Column({ space: 8 }) {
                Button(note.title).id(`open_note_${note.id}`).fontSize(20).width('100%')
                  .onClick(() => { this.selected = note; this.notice = ''; })
                Text(note.body).fontSize(15).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.padding(16).backgroundColor('#FFFFFF').borderRadius(16).width('100%')
            }
          }, (note: Note) => note.id)
        }.layoutWeight(1).width('100%')
      }
    }.padding(16).width('100%').height('100%').backgroundColor('#F3F4FA')
  }
}
