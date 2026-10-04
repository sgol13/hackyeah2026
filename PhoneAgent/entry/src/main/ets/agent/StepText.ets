/**
 * Plain-sentence text for the steps the user sees ("Open Messages", 'Tap "Send"').
 * The model-facing tool results keep their own wording; this is only for the log.
 */
import {
  TOOL_CLICK,
  TOOL_LAUNCH_APP,
  TOOL_LIST_APPS,
  TOOL_PRESS_KEY,
  TOOL_READ_SCREEN,
  TOOL_SCROLL,
  TOOL_SET_ALARM,
  TOOL_TYPE_TEXT,
  ToolAction
} from './Tools';

function twoDigits(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

const LINE = /^\[\d+\] (\S+)(?: "(.*?)")?(?: desc="(.*?)")?(?: hint="(.*?)")?(?: \(|$| @)/;

/** '"Send"' from a screen line's text, desc or hint; the lower-cased type otherwise; '' for an empty line. */
export function targetFromLine(line: string): string {
  const m = LINE.exec(line);
  if (m === null) {
    return '';
  }
  for (const part of [m[2], m[3], m[4]]) {
    if (part !== undefined && part.length > 0) {
      return `"${part}"`;
    }
  }
  return m[1].toLowerCase();
}

function capitalize(s: string): string {
  return s.length > 0 ? s.charAt(0).toUpperCase() + s.substring(1) : s;
}

export function stepText(a: ToolAction, appLabel: string, elementLine: string): string {
  const found = targetFromLine(elementLine);
  const target = found.length > 0 ? found : `item ${a.index}`;
  switch (a.name) {
    case TOOL_LIST_APPS:
      return 'Check the installed apps';
    case TOOL_LAUNCH_APP:
      return `Open ${appLabel.length > 0 ? appLabel : a.bundleName}`;
    case TOOL_READ_SCREEN:
      return 'Look at the screen';
    case TOOL_CLICK:
      return `Tap ${target}`;
    case TOOL_TYPE_TEXT:
      return `Type "${a.text}" into ${target}`;
    case TOOL_SCROLL:
      return `Scroll ${a.scrollDown ? 'down' : 'up'}`;
    case TOOL_PRESS_KEY:
      return `Press ${capitalize(a.key)}`;
    case TOOL_SET_ALARM:
      return `Set an alarm for ${twoDigits(a.hour)}:${twoDigits(a.minute)}`;
    default:
      return a.name;
  }
}
