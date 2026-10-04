import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';
import { dateText, eventTimestamp, timeText } from '../common/EventTime';

@Entry
@Component
struct Index {
  @State events: calendarManager.Event[] = [];
  @State editing: boolean = false;
  @State busy: boolean = true;
  @State ready: boolean = false;
  @State title: string = '';
  @State day: string = dateText(new Date());
  @State time: string = '17:00';
  @State duration: string = '60';
  @State notice: string = '';
  private calendar: calendarManager.Calendar | undefined = undefined;

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    this.busy = true;
    this.notice = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context,
        ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
      if (permission.authResults.some((result: number) => result !== 0)) {
        throw new Error('Calendar permission is required. Allow access to view and save events.');
      }
      const manager = calendarManager.getCalendarManager(context);
      const account: calendarManager.CalendarAccount = {
        name: 'oniro-local', type: calendarManager.CalendarType.LOCAL, displayName: 'My calendar'
      };
      const calendars = await manager.getAllCalendars();
      this.calendar = calendars.find((calendar: calendarManager.Calendar) => calendar.getAccount().name === account.name);
      if (this.calendar === undefined) {
        this.calendar = await manager.createCalendar(account);
      }
      await this.refresh();
      this.ready = true;
    } catch (error) {
      this.notice = `Could not open calendar: ${(error as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  private async refresh(): Promise<void> {
    if (this.calendar === undefined) {
      throw new Error('Calendar is unavailable.');
    }
    const events = await this.calendar.getEvents();
    this.events = events.sort((a: calendarManager.Event, b: calendarManager.Event) => a.startTime - b.startTime);
  }

  private newEvent(): void {
    this.title = '';
    this.day = dateText(new Date());
    this.time = '17:00';
    this.duration = '60';
    this.notice = '';
    this.editing = true;
  }

  private async save(): Promise<void> {
    if (this.busy || this.calendar === undefined) {
      return;
    }
    this.notice = '';
    try {
      const title = this.title.trim();
      if (title.length === 0 || title.length > 200) {
        throw new Error('Enter an event title of 1 to 200 characters.');
      }
      const start = eventTimestamp(this.day.trim(), this.time.trim());
      const minutes = Number(this.duration);
      if (!/^\d+$/.test(this.duration) || !Number.isInteger(minutes) || minutes < 1 || minutes > 10080) {
        throw new Error('Duration must be 1 to 10080 minutes.');
      }
      const event: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL, title: title,
        startTime: start, endTime: start + minutes * 60000, isAllDay: false
      };
      this.busy = true;
      const id = await this.calendar.addEvent(event);
      // Confirm the write by reading it back before displaying success.
      const saved = await this.calendar.getEvents(calendarManager.EventFilter.filterById([id]));
      if (saved.length === 0) {
        throw new Error('The event could not be verified. Check the event list before trying again.');
      }
      this.editing = false;
      this.notice = `Saved "${title}" for ${this.day} at ${this.time}.`;
      await this.refresh();
    } catch (error) {
      this.notice = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async remove(event: calendarManager.Event): Promise<void> {
    if (this.calendar === undefined || event.id === undefined || this.busy) {
      return;
    }
    this.busy = true;
    try {
      await this.calendar.deleteEvent(event.id);
      await this.refresh();
      this.notice = `Deleted "${event.title ?? ''}".`;
    } catch (error) {
      this.notice = `Could not delete event: ${(error as Error).message}`;
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text(this.editing ? 'New event' : 'Calendar').fontSize(28).fontWeight(FontWeight.Bold).layoutWeight(1)
        if (this.editing) {
          Button('Cancel').onClick(() => { this.editing = false; this.notice = ''; }).enabled(!this.busy)
        } else {
          Button('New event').id('new_event').enabled(this.ready && !this.busy).onClick(() => this.newEvent())
        }
      }.width('100%')
      Text(`Today: ${dateText(new Date())} · Phone local time`).fontSize(13).fontColor('#686474').width('100%')
      if (this.notice.length > 0) {
        Text(this.notice).id('notice').fontSize(15).width('100%')
      }
      if (this.editing) {
        Scroll() {
          Column({ space: 10 }) {
            Text('Event title').width('100%')
            TextInput({ text: this.title, placeholder: 'Event title' }).id('event_title')
              .accessibilityText('Event title').onChange((value: string) => { this.title = value; })
            Text('Date (YYYY-MM-DD)').width('100%')
            TextInput({ text: this.day, placeholder: 'YYYY-MM-DD' }).id('event_date')
              .accessibilityText('Event date YYYY-MM-DD').onChange((value: string) => { this.day = value; })
            Text('Start time (HH:mm)').width('100%')
            TextInput({ text: this.time, placeholder: 'HH:mm' }).id('event_time')
              .accessibilityText('Start time HH:mm').onChange((value: string) => { this.time = value; })
            Text('Duration (minutes)').width('100%')
            TextInput({ text: this.duration, placeholder: '60' }).id('event_duration')
              .accessibilityText('Duration in minutes').onChange((value: string) => { this.duration = value; })
            Button('Save event').id('save_event').width('100%').enabled(!this.busy).onClick(() => this.save())
          }.width('100%')
        }.layoutWeight(1).width('100%')
      } else {
        if (!this.ready && !this.busy) {
          Button('Allow calendar access').onClick(() => this.initialize())
        }
        List({ space: 12 }) {
          if (this.events.length === 0) {
            ListItem() { Text(this.busy ? 'Loading calendar…' : 'No events yet. Tap New event to add one.').fontSize(16) }
          }
          ForEach(this.events, (event: calendarManager.Event) => {
            ListItem() {
              Column({ space: 8 }) {
                Text(event.title ?? 'Event').fontSize(21).fontWeight(FontWeight.Medium).width('100%')
                Text(`${dateText(new Date(event.startTime))} ${timeText(new Date(event.startTime))} – ` +
                  `${dateText(new Date(event.endTime))} ${timeText(new Date(event.endTime))}`).fontSize(15).width('100%')
                Button('Delete event').accessibilityText(`Delete event ${event.title ?? ''}`)
                  .enabled(!this.busy).onClick(() => this.remove(event))
              }.padding(16).borderRadius(16).backgroundColor('#FFFFFF').width('100%')
            }
          }, (event: calendarManager.Event) => `${event.id}`)
        }.layoutWeight(1).width('100%')
      }
    }.padding(20).width('100%').height('100%').backgroundColor('#F6F5FB').alignItems(HorizontalAlign.Start)
  }
}
