import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { dateText, eventTimestamp, timeText } from '../common/EventTime';

@Entry
@Component
struct Index {
  @State reminders: reminderAgentManager.ReminderInfo[] = [];
  @State editing: boolean = false;
  @State busy: boolean = false;
  @State title: string = '';
  @State day: string = dateText(new Date());
  @State time: string = '10:00';
  @State notice: string = '';

  aboutToAppear(): void { this.refresh(); }

  private async refresh(): Promise<void> {
    try { this.reminders = await reminderAgentManager.getAllValidReminders(); }
    catch (error) { this.notice = `Could not load reminders: ${(error as Error).message}`; }
  }

  private newReminder(): void {
    this.title = ''; this.day = dateText(new Date()); this.time = '10:00'; this.notice = ''; this.editing = true;
  }

  private when(info: reminderAgentManager.ReminderInfo): string {
    const request = info.reminderReq as reminderAgentManager.ReminderRequestCalendar;
    const date = request.dateTime;
    if (date === undefined) { return request.content ?? ''; }
    const local = new Date(date.year, date.month - 1, date.day, date.hour, date.minute);
    return `${dateText(local)} ${timeText(local)}`;
  }

  private async save(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.notice = '';
    let published: number | undefined = undefined;
    try {
      const title = this.title.trim();
      if (title.length === 0 || title.length > 100) { throw new Error('Enter a reminder title of 1 to 100 characters.'); }
      const timestamp = eventTimestamp(this.day.trim(), this.time.trim());
      if (timestamp <= Date.now()) { throw new Error('Choose a future date and time.'); }
      const bundle: notificationManager.BundleOption = { bundle: 'com.hackyeah.reminders' };
      if (!(await notificationManager.isNotificationEnabled(bundle))) {
        await notificationManager.setNotificationEnable(bundle, true);
      }
      const date = new Date(timestamp);
      const request: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(),
          hour: date.getHours(), minute: date.getMinutes() },
        repeatMonths: [], repeatDays: [], title: title, content: `${this.day} ${this.time}`,
        ringDuration: 30, snoozeTimes: 0,
        wantAgent: { pkgName: 'com.hackyeah.reminders', abilityName: 'EntryAbility' },
        actionButton: [{ title: 'Dismiss', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }]
      };
      published = await reminderAgentManager.publishReminder(request);
      const saved = await reminderAgentManager.getAllValidReminders();
      if (!saved.some((info: reminderAgentManager.ReminderInfo) => info.reminderId === published)) {
        throw new Error('The scheduled reminder could not be verified.');
      }
      this.reminders = saved; this.editing = false;
      this.notice = `Scheduled "${title}" for ${this.day} at ${this.time}.`;
    } catch (error) {
      this.notice = `${(error as Error).message}${published === undefined ? '' : ' A reminder was submitted; check the list before retrying.'}`;
    } finally { this.busy = false; }
  }

  private remove(info: reminderAgentManager.ReminderInfo): void {
    AlertDialog.show({ title: 'Delete reminder?', message: `Cancel "${info.reminderReq.title ?? 'Reminder'}"?`,
      primaryButton: { value: 'Cancel', action: () => {} },
      secondaryButton: { value: 'Delete', action: () => {
        this.busy = true;
        reminderAgentManager.cancelReminder(info.reminderId).then(() => this.refresh())
          .catch((error: Error) => { this.notice = error.message; }).finally(() => { this.busy = false; });
      } } });
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Text(this.editing ? 'New reminder' : 'Reminders').fontSize(28).fontWeight(FontWeight.Bold).layoutWeight(1)
        if (this.editing) { Button('Cancel').onClick(() => { this.editing = false; this.notice = ''; }).enabled(!this.busy) }
        else { Button('New reminder').id('new_reminder').onClick(() => this.newReminder()).enabled(!this.busy) }
      }.width('100%')
      if (this.notice.length > 0) { Text(this.notice).id('notice').fontSize(15).width('100%') }
      if (this.editing) {
        Scroll() {
          Column({ space: 12 }) {
            Text('Reminder title').width('100%')
            TextInput({ text: this.title, placeholder: 'Reminder title' }).id('reminder_title')
              .accessibilityText('Reminder title').onChange((value: string) => { this.title = value; })
            Text('Date (YYYY-MM-DD)').width('100%')
            TextInput({ text: this.day, placeholder: 'YYYY-MM-DD' }).id('reminder_date')
              .accessibilityText('Reminder date YYYY-MM-DD').onChange((value: string) => { this.day = value; })
            Text('Time (HH:mm)').width('100%')
            TextInput({ text: this.time, placeholder: 'HH:mm' }).id('reminder_time')
              .accessibilityText('Reminder time HH:mm').onChange((value: string) => { this.time = value; })
            Button('Save reminder').id('save_reminder').width('100%').enabled(!this.busy).onClick(() => { this.save(); })
          }.width('100%')
        }.layoutWeight(1).width('100%')
      } else {
        List({ space: 12 }) {
          if (this.reminders.length === 0) { ListItem() { Text('No reminders yet. Tap New reminder to add one.') } }
          ForEach(this.reminders, (info: reminderAgentManager.ReminderInfo) => {
            ListItem() {
              Column({ space: 8 }) {
                Text(info.reminderReq.title ?? 'Reminder').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
                Text(`Scheduled: ${this.when(info)}`).fontSize(16).width('100%')
                Button('Delete reminder').accessibilityText(`Delete ${info.reminderReq.title ?? 'Reminder'}`)
                  .enabled(!this.busy).onClick(() => this.remove(info))
              }.padding(16).width('100%').backgroundColor('#FFFFFF').borderRadius(16)
            }
          }, (info: reminderAgentManager.ReminderInfo) => `${info.reminderId}`)
        }.layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%').padding(16).backgroundColor('#F3F4FA')
  }
}
