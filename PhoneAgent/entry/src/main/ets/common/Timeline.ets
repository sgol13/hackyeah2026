/** Groups the agent log into the steps the user sees: each thought is folded under the step that follows it. */
import { LOG_THOUGHT } from '../agent/AgentLoop';
import { LogEntry } from './Bridge';

export const STEP_THINKING = 'Thinking';
const MAX_LINE = 120;

export interface Step {
  seq: number;
  kind: string;
  text: string;
  thoughts: string[];
}

export function buildTimeline(entries: LogEntry[]): Step[] {
  const steps: Step[] = [];
  let pending: string[] = [];
  for (const e of entries) {
    if (e.kind === LOG_THOUGHT) {
      pending.push(e.text);
      continue;
    }
    steps.push({ seq: e.seq, kind: e.kind, text: e.text, thoughts: pending });
    pending = [];
  }
  if (pending.length > 0) {
    steps.push({ seq: entries[entries.length - 1].seq, kind: LOG_THOUGHT, text: STEP_THINKING, thoughts: pending });
  }
  return steps;
}

/** The newest step as one short line, for the pill. */
export function currentStepText(steps: Step[]): string {
  if (steps.length === 0) {
    return '';
  }
  const line = steps[steps.length - 1].text.replace(/\s+/g, ' ').trim();
  return line.length > MAX_LINE ? line.substring(0, MAX_LINE - 1) + '…' : line;
}
