/**
 * Tool definitions sent to the model, and validation of the model's tool calls.
 * Anything the model sends that does not fit the schema becomes a ParseResult
 * with an error, which the agent loop returns as an is_error tool_result.
 */
import { ContentBlock, JsonSchemaProperty, ToolDef } from './Anthropic';

export const TOOL_LIST_APPS = 'list_apps';
export const TOOL_LAUNCH_APP = 'launch_app';
export const TOOL_READ_SCREEN = 'read_screen';
export const TOOL_CLICK = 'click';
export const TOOL_TYPE_TEXT = 'type_text';
export const TOOL_SCROLL = 'scroll';
export const TOOL_PRESS_KEY = 'press_key';
export const TOOL_SET_ALARM = 'set_alarm';
export const TOOL_FINISH = 'finish';

const MAX_LABEL_LEN = 100;

const MAX_TEXT_LEN = 2000;
const MAX_INDEX = 10000;

function prop(type: string, description: string): JsonSchemaProperty {
  return { type: type, description: description };
}

function enumProp(values: string[], description: string): JsonSchemaProperty {
  return { type: 'string', enum: values, description: description };
}

function tool(name: string, description: string, properties: Record<string, JsonSchemaProperty>,
  required: string[]): ToolDef {
  return {
    name: name,
    description: description,
    input_schema: { type: 'object', properties: properties, required: required, additionalProperties: false }
  };
}

const NO_PROPS: Record<string, JsonSchemaProperty> = {};

export const TOOLS: ToolDef[] = [
  tool(TOOL_LIST_APPS,
    'List the apps installed on the phone as "Name (bundle.name)". Call this when you do not know the bundle name of the app you need.',
    NO_PROPS, []),
  tool(TOOL_LAUNCH_APP,
    'Open an app by its bundle name (from list_apps). Returns the screen after the app opened.',
    { 'bundle_name': prop('string', 'Bundle name, e.g. com.ohos.settings') }, ['bundle_name']),
  tool(TOOL_READ_SCREEN,
    'Return the current screen without doing anything. Use it when you need a fresh view, e.g. after something was loading.',
    NO_PROPS, []),
  tool(TOOL_CLICK,
    'Tap the element with this index from the most recent screen. Returns the new screen.',
    { 'index': prop('integer', 'Element index from the most recent screen') }, ['index']),
  tool(TOOL_TYPE_TEXT,
    'Replace the content of an editable element (flag "edit") with the given text. The field is focused first. Returns the new screen.',
    {
      'index': prop('integer', 'Index of an editable element from the most recent screen'),
      'text': prop('string', 'The full text the field should contain')
    }, ['index', 'text']),
  tool(TOOL_SCROLL,
    'Scroll a scrollable element (flag "scroll") to reveal more content. Returns the new screen.',
    {
      'index': prop('integer', 'Index of a scrollable element from the most recent screen'),
      'direction': enumProp(['down', 'up'], '"down" reveals content further down the list')
    }, ['index', 'direction']),
  tool(TOOL_PRESS_KEY,
    'Press a system key: "back" goes back or closes the keyboard, "home" goes to the home screen. Returns the new screen.',
    { 'key': enumProp(['back', 'home'], 'Which key to press') }, ['key']),
  tool(TOOL_SET_ALARM,
    'Set an alarm with the phone\'s system alarm service (no app needed): at the given time the phone rings and shows a notification. ' +
      'Use it for any alarm or wake-up request. The alarm rings once, at the next occurrence of that time.',
    {
      'hour': prop('integer', 'Hour, 0-23 (24-hour clock)'),
      'minute': prop('integer', 'Minute, 0-59'),
      'label': prop('string', 'Optional short name for the alarm, in the user\'s language')
    }, ['hour', 'minute']),
  tool(TOOL_FINISH,
    'Call once when the task is complete, or when it cannot be completed. This ends the task.',
    {
      'success': prop('boolean', 'true if the task was completed'),
      'summary': prop('string', 'One or two sentences for the user describing what you did or why you stopped')
    }, ['success', 'summary'])
];

/** A validated tool call. Only the fields relevant to `name` are meaningful. */
export interface ToolAction {
  name: string;
  index: number;
  text: string;
  bundleName: string;
  scrollDown: boolean;
  key: string;
  success: boolean;
  /** set_alarm only */
  hour: number;
  minute: number;
}

export interface ParseResult {
  action?: ToolAction;
  error?: string;
}

function fail(error: string): ParseResult {
  return { error: error };
}

function getIndex(input: Record<string, Object>): number | string {
  const v = input['index'];
  if (typeof v !== 'number' || !Number.isInteger(v as number)) {
    return '"index" must be an integer';
  }
  const n = v as number;
  if (n < 0 || n > MAX_INDEX) {
    return `"index" ${n} is out of range`;
  }
  return n;
}

function getString(input: Record<string, Object>, key: string, maxLen: number): string | undefined {
  const v = input[key];
  if (typeof v !== 'string') {
    return undefined;
  }
  const s = v as string;
  return s.length <= maxLen ? s : undefined;
}

function newAction(name: string): ToolAction {
  return {
    name: name, index: -1, text: '', bundleName: '', scrollDown: true, key: '', success: false, hour: -1, minute: -1
  };
}

function getIntIn(input: Record<string, Object>, key: string, min: number, max: number): number | undefined {
  const v = input[key];
  if (typeof v !== 'number' || !Number.isInteger(v as number) || (v as number) < min || (v as number) > max) {
    return undefined;
  }
  return v as number;
}

/** Validates a tool_use block from the model. Never throws. */
export function parseToolCall(block: ContentBlock): ParseResult {
  const name = block.name ?? '';
  const input = block.input;
  if (input === undefined || input === null || typeof input !== 'object') {
    return fail(`Tool input for "${name}" must be a JSON object`);
  }
  const action = newAction(name);
  switch (name) {
    case TOOL_LIST_APPS:
    case TOOL_READ_SCREEN:
      return { action: action };
    case TOOL_LAUNCH_APP: {
      const bundle = getString(input, 'bundle_name', 200);
      if (bundle === undefined || !/^[A-Za-z][A-Za-z0-9_.]*$/.test(bundle)) {
        return fail('"bundle_name" must be a bundle name like com.ohos.settings');
      }
      action.bundleName = bundle;
      return { action: action };
    }
    case TOOL_CLICK: {
      const idx = getIndex(input);
      if (typeof idx === 'string') {
        return fail(idx as string);
      }
      action.index = idx as number;
      return { action: action };
    }
    case TOOL_TYPE_TEXT: {
      const idx = getIndex(input);
      if (typeof idx === 'string') {
        return fail(idx as string);
      }
      const text = getString(input, 'text', MAX_TEXT_LEN);
      if (text === undefined) {
        return fail(`"text" must be a string of at most ${MAX_TEXT_LEN} characters`);
      }
      action.index = idx as number;
      action.text = text;
      return { action: action };
    }
    case TOOL_SCROLL: {
      const idx = getIndex(input);
      if (typeof idx === 'string') {
        return fail(idx as string);
      }
      const dir = getString(input, 'direction', 10);
      if (dir !== 'down' && dir !== 'up') {
        return fail('"direction" must be "down" or "up"');
      }
      action.index = idx as number;
      action.scrollDown = dir === 'down';
      return { action: action };
    }
    case TOOL_PRESS_KEY: {
      const key = getString(input, 'key', 10);
      if (key !== 'back' && key !== 'home') {
        return fail('"key" must be "back" or "home"');
      }
      action.key = key;
      return { action: action };
    }
    case TOOL_SET_ALARM: {
      const hour = getIntIn(input, 'hour', 0, 23);
      const minute = getIntIn(input, 'minute', 0, 59);
      if (hour === undefined || minute === undefined) {
        return fail('"hour" must be an integer 0-23 and "minute" an integer 0-59');
      }
      const label = input['label'] === undefined ? '' : getString(input, 'label', MAX_LABEL_LEN);
      if (label === undefined) {
        return fail(`"label" must be a string of at most ${MAX_LABEL_LEN} characters`);
      }
      action.hour = hour;
      action.minute = minute;
      action.text = label;
      return { action: action };
    }
    case TOOL_FINISH: {
      const success = input['success'];
      const summary = getString(input, 'summary', MAX_TEXT_LEN);
      if (typeof success !== 'boolean' || summary === undefined) {
        return fail('"success" must be a boolean and "summary" a string');
      }
      action.success = success as boolean;
      action.text = summary;
      return { action: action };
    }
    default:
      return fail(`Unknown tool "${name}". Available tools: ${TOOLS.map((t: ToolDef) => t.name).join(', ')}`);
  }
}
