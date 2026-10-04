/** Merges the agent service's STATUS events into the current log (shared by the app and the overlay). */
import { AgentStatus, LogEntry } from './Bridge';

export class StatusTracker {
  entries: LogEntry[] = [];
  running: boolean = false;
  /** statuses received; any status proves the service is listening */
  seen: number = 0;
  version: number = 0;
  private instance: number = 0;

  /** Applies one STATUS payload; false if it was unparsable, stale or a duplicate. */
  apply(data: string): boolean {
    let status: AgentStatus;
    try {
      status = JSON.parse(data) as AgentStatus;
    } catch (e) {
      return false;
    }
    this.seen++;
    if (status.instance === this.instance && status.version <= this.version) {
      return false;
    }
    this.instance = status.instance;
    this.version = status.version;
    this.running = status.running;
    if (status.full) {
      this.entries = status.entries;
      return true;
    }
    let next = this.entries.slice();
    const lastSeq = next.length > 0 ? next[next.length - 1].seq : 0;
    for (const e of status.entries) {
      if (e.seq > lastSeq || e.seq === 1) {
        if (e.seq === 1) {
          next = [];
        }
        next.push(e);
      }
    }
    this.entries = next;
    return true;
  }
}
