/**
 * UI <-> agent-service messaging over common events.
 * The agent loop runs inside the accessibility extension (its own process), so it
 * keeps working while another app is in the foreground. Events are restricted to
 * this bundle in both directions (publish bundleName + subscriber publisherBundleName),
 * so other apps can neither start tasks nor read the log.
 */
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';

export const OWN_BUNDLE = 'com.hackyeah.phoneagent';
export const OWN_A11Y_ABILITY = 'com.hackyeah.phoneagent/AgentA11y';

/** UI -> service: start a task (data: RunRequest JSON) */
export const EVT_RUN = 'com.hackyeah.phoneagent.RUN';
/** UI -> service: stop the running task */
export const EVT_STOP = 'com.hackyeah.phoneagent.STOP';
/** UI -> service: please republish the full status */
export const EVT_SYNC = 'com.hackyeah.phoneagent.SYNC';
/** service -> UI: log entries (data: AgentStatus JSON) */
export const EVT_STATUS = 'com.hackyeah.phoneagent.STATUS';

export interface RunRequest {
  task: string;
  /** provider id, see agent/Providers.ets */
  provider: string;
  model: string;
}

export interface LogEntry {
  seq: number;
  kind: string;
  text: string;
}

export interface AgentStatus {
  /** identifies the service instance; version restarts when it changes */
  instance: number;
  /** increases with every status the instance publishes; lets the UI drop stale ones */
  version: number;
  running: boolean;
  /** true: entries is the whole log of the current/last task; false: entries are new ones */
  full: boolean;
  entries: LogEntry[];
}

export function publishEvent(event: string, data: string): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const options: commonEventManager.CommonEventPublishData = { data: data, bundleName: OWN_BUNDLE };
    commonEventManager.publish(event, options, (err: BusinessError) => {
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
}

export type EventHandler = (event: string, data: string) => void;

export async function subscribeEvents(events: string[],
  handler: EventHandler): Promise<commonEventManager.CommonEventSubscriber> {
  const info: commonEventManager.CommonEventSubscribeInfo = { events: events, publisherBundleName: OWN_BUNDLE };
  const sub = await commonEventManager.createSubscriber(info);
  commonEventManager.subscribe(sub, (err: BusinessError, data: commonEventManager.CommonEventData) => {
    if (!err) {
      handler(data.event, data.data ?? '');
    }
  });
  return sub;
}

export function unsubscribeEvents(sub: commonEventManager.CommonEventSubscriber | undefined): void {
  if (sub !== undefined) {
    commonEventManager.unsubscribe(sub);
  }
}
