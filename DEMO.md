# Birthday presentation

Use this exact English prompt in Oniro Agent:

> Check in notes what time grandma’s birthday party is, create an event in the calendar and set a reminder to buy a gift. Send SMS to the grandma that I will come

## Prepare before presenting

Follow README Setup, start the emulator, and build/install Oniro Agent plus the Calendar, Notes and Reminders companions. Configure an AI provider key in Oniro Agent. The image includes Contacts and Messages.

| App | Bundle | Launch ability |
|---|---|---|
| Oniro Agent | `com.hackyeah.phoneagent` | `EntryAbility` |
| Notes | `com.hackyeah.notes` | `EntryAbility` |
| Calendar | `com.hackyeah.calendar` | `EntryAbility` |
| Reminders | `com.hackyeah.reminders` | `EntryAbility` |
| Contacts | `com.ohos.contacts` | `com.ohos.contacts.MainAbility` |
| Messages | `com.ohos.mms` | `com.ohos.mms.MainAbility` |

The existing demo contacts have been renamed to Grandma, Mom, Dad, Grandpa and Jacob, keeping numbers 600100200 through 600100204 respectively. On a fresh image add Grandma with 600100200 in Contacts before using this prompt.

Run from the repository root:

```powershell
.\scripts\prepare-demo.ps1
```

It checks all six bundles and refreshes one specifically identified presentation note in the debug Notes app. It does not remove contacts, events, reminders or other notes. Open **Grandma birthday party** and check its contents:

- Party: tomorrow's date, **17:00–18:00**, at Grandma's house.
- Calendar title: **Grandma birthday party**.
- Gift reminder: tomorrow's date at **10:00**.
- Recipient: **Grandma** in Contacts.

These facts are in the actual saved note; the agent reads the note during the task. Rerun preparation on the presentation day so tomorrow's date is current. Allow Calendar access when first asked. Open Reminders once to confirm there is no error loading the system schedule.

## Optional: show a user skill

Demo-specific knowledge belongs in a user skill, not in the app's code. In Oniro Agent open **Skills → +** and add:

- **Name:** `birthday planning`
- **Description:** `Use when planning a birthday or party from a note`
- **Body:** `Read the note first. Create the calendar event with the exact title, date and time from the note. If the note says when to buy a gift, create a separate reminder at that time. Then message the person.`

The agent lists enabled skills in its prompt and reads this one with `read_skill` when the task matches; the read shows up in the timeline.

## Present

Return to Oniro Agent, enter the prompt and tap Run. The expected sequence is reading Notes, saving and verifying the calendar event, scheduling and verifying **Buy a gift**, selecting Grandma from the Messages contact picker, composing an English first-person SMS, and tapping Send once. The agent may choose another order while completing all parts.

The emulator has no SIM, so the SMS is not delivered. The agent fills in the recipient and message, taps Send once without retrying, and says in its summary that delivery could not be confirmed. Calendar entries and reminders are real system records.

After completion, show Calendar and Reminders to demonstrate the saved date/time. The task prompt becomes empty again; the timeline remains available.

## Reset for another rehearsal

Delete only the newly created **Grandma birthday party** event from Calendar and the newly created gift reminder from Reminders. Confirm reminder deletion. In Messages, discard the unsent rehearsal draft if present. Keep Grandma and the prepared note. Run preparation again if the phone's date changed. Repeated runs otherwise create duplicate events/reminders.

The starting calendar should contain exactly one event named **job interview**. Keep it when cleaning up a rehearsal; remove the birthday event and any other previous test events before presenting.

## Verified rehearsal — 2026-10-04

The exact prompt completed on the Oniro emulator with the configured Claude provider. It read the saved note, created **Grandma birthday party** for **2026-10-05 17:00–18:00**, scheduled **Buy a gift for Grandma** for **2026-10-05 10:00**, selected **Grandma / 600100200**, composed **Hi Grandma, I will come to your birthday party tomorrow at 17:00!**, and tapped Send once. The final summary reported that SMS delivery was not confirmed. Calendar and Reminders still showed the records after their apps were stopped and relaunched.

The rehearsal event, reminder and SMS draft were removed afterward. The prepared note and five English contacts remain ready for another run. Earlier calendar test titles were translated to **Party** and **Grandma name day**, preserving their dates and durations. 

The later presentation setup replaces those previous calendar events with a single **job interview** event for **2026-10-05 09:00–10:00**. Calendar was stopped and reopened to verify that this is its only saved event.

Current test count: see README *Check*.
