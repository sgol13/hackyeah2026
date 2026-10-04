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

Run from the PhoneAgent project directory:

```powershell
.\scripts\prepare-demo.ps1
```

It checks all six bundles and refreshes one specifically identified presentation note in the debug Notes app. It does not remove contacts, events, reminders or other notes. Open **Grandma birthday party** and check its contents:

- Party: tomorrow's date, **17:00–18:00**, at Grandma's house.
- Calendar title: **Grandma birthday party**.
- Gift reminder: tomorrow's date at **10:00**.
- Recipient: **Grandma** in Contacts.

These facts are in the actual saved note; the agent reads the note during the task. Rerun preparation on the presentation day so tomorrow's date is current. Allow Calendar access when first asked. Open Reminders once to confirm there is no error loading the system schedule.

## Present

Return to Oniro Agent, enter the prompt and tap Run. The expected sequence is reading Notes, saving and verifying the calendar event, scheduling and verifying **Buy a gift**, selecting Grandma from the Messages contact picker, composing an English first-person SMS, and tapping Send once. The agent may choose another order while completing all parts.

The Oniro emulator shows **No SIM**. The SMS UI and Send action can be shown, but actual SMS delivery requires a supported phone and active SIM. The completion summary must state that delivery was not confirmed. Calendar entries and reminders are real system records.

After completion, show Calendar and Reminders to demonstrate the saved date/time. The task prompt becomes empty again; the timeline remains available.

## Reset for another rehearsal

Delete only the newly created **Grandma birthday party** event from Calendar and the newly created gift reminder from Reminders. Confirm reminder deletion. In Messages, discard the unsent rehearsal draft if present. Keep Grandma and the prepared note. Run preparation again if the phone's date changed. Repeated runs otherwise create duplicate events/reminders.
