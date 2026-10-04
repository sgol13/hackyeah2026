/**
 * Platform-independent screen model + serializer.
 * The accessibility layer converts on-screen elements into UiNode records (in
 * depth-first order); this file turns them into the compact text the LLM sees, e.g.
 *   [3] Button "Send" (click) @180,690
 *   [4] Flex "WLAN · Off" (click) @180,192      <- texts of a tappable row folded in
 * Kept free of OS imports so it can be unit tested.
 */

export interface UiNode {
  /** depth in the accessibility tree (root = 0); nodes are in depth-first order */
  depth: number;
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
  /** lines[i] describes the element shown as [i] */
  lines: string[];
  /** indexMap[i] = position in the input node array of the element shown as [i] */
  indexMap: number[];
  truncated: boolean;
}

const MAX_TEXT = 80;
// Reading note/message content must preserve details beyond a short control label.
const MAX_CONTENT_TEXT = 4000;
const MAX_FOLDED_TEXTS = 3;
const FOLD_SEPARATOR = ' · ';

function clip(s: string, limit: number = MAX_TEXT): string {
  const oneLine = s.replace(/\s+/g, ' ').trim();
  return oneLine.length > limit ? oneLine.substring(0, limit - 1) + '…' : oneLine;
}

function isVisible(n: UiNode): boolean {
  return n.visible && n.width > 0 && n.height > 0;
}

/** Elements the user can act on directly (lists are containers, not targets to fold into). */
function isActionable(n: UiNode): boolean {
  return n.clickable || n.editable || n.checkable;
}

function hasOwnLabel(n: UiNode): boolean {
  return n.text.trim().length > 0 || n.desc.trim().length > 0;
}

export function isInteresting(n: UiNode): boolean {
  if (!isVisible(n)) {
    return false;
  }
  return n.clickable || n.editable || n.scrollable || n.checkable ||
    n.text.trim().length > 0 || n.desc.trim().length > 0 || n.hint.trim().length > 0;
}

/** One line for an element; `label` (folded child texts) is used when the node has no text. */
export function describeNode(index: number, n: UiNode, label?: string): string {
  let line = `[${index}] ${n.type.length > 0 ? n.type : 'View'}`;
  const contentLimit = n.editable || (!isActionable(n) && n.text.trim().length > 0) ? MAX_CONTENT_TEXT : MAX_TEXT;
  const text = clip(n.text.trim().length > 0 ? n.text : (label ?? ''), contentLimit);
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

/**
 * For every plain text node, finds its nearest actionable ancestor. If that
 * ancestor has no label of its own, the text is folded into it (up to 3 texts)
 * and not listed separately; if the ancestor already shows the same text, the
 * duplicate child is dropped.
 */
function foldLabels(nodes: UiNode[]): FoldResult {
  const labels: string[][] = nodes.map((): string[] => []);
  const absorbed: boolean[] = nodes.map((): boolean => false);
  const stack: number[] = [];
  for (let j = 0; j < nodes.length; j++) {
    const n = nodes[j];
    while (stack.length > 0 && nodes[stack[stack.length - 1]].depth >= n.depth) {
      stack.pop();
    }
    const owner = stack.length > 0 ? stack[stack.length - 1] : -1;
    if (owner >= 0 && !isActionable(n) && !n.scrollable && isVisible(n)) {
      const own = n.text.trim().length > 0 ? n.text.trim() : n.desc.trim();
      if (own.length > 0) {
        const ownerNode = nodes[owner];
        if (!hasOwnLabel(ownerNode)) {
          if (labels[owner].length < MAX_FOLDED_TEXTS) {
            labels[owner].push(own);
          }
          absorbed[j] = true;
        } else if (ownerNode.text.trim() === own || ownerNode.desc.trim() === own) {
          absorbed[j] = true;
        }
      }
    }
    if (isActionable(n)) {
      stack.push(j);
    }
  }
  return { labels: labels.map((l: string[]): string => l.join(FOLD_SEPARATOR)), absorbed: absorbed };
}

interface FoldResult {
  labels: string[];
  absorbed: boolean[];
}

export function serializeScreen(nodes: UiNode[], maxItems: number): SerializedScreen {
  const fold = foldLabels(nodes);
  const lines: string[] = [];
  const indexMap: number[] = [];
  let truncated = false;
  for (let i = 0; i < nodes.length; i++) {
    if (fold.absorbed[i] || !isInteresting(nodes[i])) {
      continue;
    }
    if (indexMap.length >= maxItems) {
      truncated = true;
      break;
    }
    lines.push(describeNode(indexMap.length, nodes[i], fold.labels[i]));
    indexMap.push(i);
  }
  const textLines = lines.slice();
  if (truncated) {
    textLines.push(`... (truncated to ${maxItems} elements)`);
  }
  if (textLines.length === 0) {
    textLines.push('(no readable elements on screen)');
  }
  return { text: textLines.join('\n'), lines: lines, indexMap: indexMap, truncated: truncated };
}
