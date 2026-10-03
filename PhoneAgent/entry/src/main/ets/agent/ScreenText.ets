/**
 * Platform-independent screen model + serializer.
 * The accessibility layer converts on-screen elements into UiNode records; this
 * file turns them into the compact text the LLM sees, e.g.
 *   [3] Button "Send" (click) @180,690
 * Kept free of OS imports so it can be unit tested.
 */

export interface UiNode {
  type: string;
  text: string;
  desc: string;
  hint: string;
  clickable: boolean;
  editable: boolean;
  scrollable: boolean;
  checkable: boolean;
  checked: boolean;
  focused: boolean;
  visible: boolean;
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface SerializedScreen {
  text: string;
  /** indexMap[i] = position in the input node array of the element shown as [i] */
  indexMap: number[];
  truncated: boolean;
}

const MAX_TEXT = 80;

function clip(s: string): string {
  const oneLine = s.replace(/\s+/g, ' ').trim();
  return oneLine.length > MAX_TEXT ? oneLine.substring(0, MAX_TEXT - 1) + '…' : oneLine;
}

export function isInteresting(n: UiNode): boolean {
  if (!n.visible || n.width <= 0 || n.height <= 0) {
    return false;
  }
  return n.clickable || n.editable || n.scrollable || n.checkable ||
    n.text.trim().length > 0 || n.desc.trim().length > 0 || n.hint.trim().length > 0;
}

export function describeNode(index: number, n: UiNode): string {
  let line = `[${index}] ${n.type.length > 0 ? n.type : 'View'}`;
  const text = clip(n.text);
  const desc = clip(n.desc);
  const hint = clip(n.hint);
  if (text.length > 0) {
    line += ` "${text}"`;
  }
  if (desc.length > 0 && desc !== text) {
    line += ` desc="${desc}"`;
  }
  if (hint.length > 0 && hint !== text) {
    line += ` hint="${hint}"`;
  }
  const flags: string[] = [];
  if (n.clickable) {
    flags.push('click');
  }
  if (n.editable) {
    flags.push('edit');
  }
  if (n.scrollable) {
    flags.push('scroll');
  }
  if (n.checkable) {
    flags.push(n.checked ? 'checked' : 'unchecked');
  }
  if (n.focused) {
    flags.push('focused');
  }
  if (flags.length > 0) {
    line += ` (${flags.join(',')})`;
  }
  const cx = Math.round(n.left + n.width / 2);
  const cy = Math.round(n.top + n.height / 2);
  return `${line} @${cx},${cy}`;
}

export function serializeScreen(nodes: UiNode[], maxItems: number): SerializedScreen {
  const lines: string[] = [];
  const indexMap: number[] = [];
  let truncated = false;
  for (let i = 0; i < nodes.length; i++) {
    if (!isInteresting(nodes[i])) {
      continue;
    }
    if (indexMap.length >= maxItems) {
      truncated = true;
      break;
    }
    lines.push(describeNode(indexMap.length, nodes[i]));
    indexMap.push(i);
  }
  if (truncated) {
    lines.push(`... (truncated to ${maxItems} elements)`);
  }
  if (lines.length === 0) {
    lines.push('(no readable elements on screen)');
  }
  return { text: lines.join('\n'), indexMap: indexMap, truncated: truncated };
}
