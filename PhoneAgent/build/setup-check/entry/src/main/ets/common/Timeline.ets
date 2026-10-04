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

function oneLine(text: string): string {
  const line = text.replace(/\s+/g, ' ').trim();
  return line.length > MAX_LINE ? line.substring(0, MAX_LINE - 1) + '…' : line;
}

/** The newest step as one short line, for the pill. */
export function currentStepText(steps: Step[]): string {
  return steps.length === 0 ? '' : oneLine(steps[steps.length - 1].text);
}

/** The model's latest thought (of the newest step that has one) as one short line, for the pill. */
export function currentThoughtText(steps: Step[]): string {
  for (let i = steps.length - 1; i >= 0; i--) {
    const t = steps[i].thoughts;
    if (t.length > 0) {
      return oneLine(t[t.length - 1]);
    }
  }
  return '';
}
