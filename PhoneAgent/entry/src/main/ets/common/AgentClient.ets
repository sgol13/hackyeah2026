/**
 * Controls the agent service (our accessibility extension) for both front ends: the app and the overlay.
 * Every call that can fail resolves to '' on success or to a message for the user.
 */
import { config } from '@kit.AccessibilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { EVT_RUN, EVT_STOP, EVT_SYNC, OWN_A11Y_ABILITY, publishEvent, RunRequest } from './Bridge';
import { StatusTracker } from './StatusTracker';

const ERR_ALREADY_ENABLED = 9300002;
const SERVICE_ACK_TIMEOUT_MS = 5000;
const SERVICE_PING_TIMEOUT_MS = 8000;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

export class AgentClient {
  private tracker: StatusTracker;

  constructor(tracker: StatusTracker) {
    this.tracker = tracker;
  }

  /** System API (WRITE_ACCESSIBILITY_CONFIG): switch on our own accessibility extension. */
  async enableService(): Promise<string> {
    try {
      await config.enableAbility(OWN_A11Y_ABILITY, ['retrieve', 'gesture']);
      return '';
    } catch (e) {
      const err = e as BusinessError;
      return err.code === ERR_ALREADY_ENABLED ? '' : `Agent service unavailable (${err.code}): ${err.message}`;
    }
  }

  /** Reconnects a service process that is enabled but not listening (e.g. after it was killed). */
  async restartService(): Promise<string> {
    try {
      await config.disableAbility(OWN_A11Y_ABILITY);
    } catch (e) {
      // not enabled: fine, enable below
    }
    return this.enableService();
  }

  /** Pings the service with SYNC until it answers with a status, or the timeout passes. */
  async waitForService(timeoutMs: number): Promise<boolean> {
    const before = this.tracker.seen;
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        await publishEvent(EVT_SYNC, '');
      } catch (e) {
        // keep trying until the deadline
      }
      for (let i = 0; i < 10 && Date.now() < deadline; i++) {
        await sleep(100);
        if (this.tracker.seen > before) {
          return true;
        }
      }
    }
    return false;
  }

  /** Starts a task and waits until the service acknowledges it with a status. */
  async run(req: RunRequest): Promise<string> {
    // Make sure the service is listening (e.g. right after boot it may still be connecting).
    if (!(await this.waitForService(SERVICE_PING_TIMEOUT_MS))) {
      await this.restartService();
      if (!(await this.waitForService(2 * SERVICE_PING_TIMEOUT_MS))) {
        return 'The agent service is not responding. Try again in a moment.';
      }
    }
    const versionBefore = this.tracker.version;
    try {
      await publishEvent(EVT_RUN, JSON.stringify(req));
    } catch (e) {
      return 'Could not reach the agent service.';
    }
    // The service answers every RUN with a status; if none arrives it was not listening yet.
    const deadline = Date.now() + SERVICE_ACK_TIMEOUT_MS;
    while (Date.now() < deadline) {
      await sleep(100);
      if (this.tracker.version !== versionBefore) {
        return '';
      }
    }
    await this.restartService();
    return 'The agent service did not respond. It is being restarted, try again in a moment.';
  }

  async stop(): Promise<string> {
    try {
      await publishEvent(EVT_STOP, '');
      return '';
    } catch (e) {
      return 'Could not reach the agent service.';
    }
  }

  /** Asks the service to republish the full log. */
  sync(): void {
    publishEvent(EVT_SYNC, '').catch(() => {
    });
  }
}
