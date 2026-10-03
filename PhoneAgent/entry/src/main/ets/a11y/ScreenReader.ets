import {
  AccessibilityAction,
  AccessibilityElement,
  AccessibilityExtensionContext,
  Parameter
} from '@kit.AccessibilityKit';
import { UiNode } from '../agent/ScreenText';

/** Raw accessibility nodes of the active window, in depth-first (reading) order. */
export interface ScreenSnapshot {
  bundleName: string;
  nodes: UiNode[];
  elements: AccessibilityElement[];
}

const MAX_RAW_NODES = 800;
const MAX_DEPTH = 60;

function str(v: string | undefined): string {
  return v ?? '';
}

function toNode(el: AccessibilityElement): UiNode {
  const r = el.rect;
  return {
    type: str(el.componentType),
    text: str(el.text),
    desc: str(el.accessibilityText).length > 0 ? str(el.accessibilityText) : str(el.description),
    hint: str(el.hintText),
    clickable: el.clickable ?? false,
    editable: el.editable ?? false,
    scrollable: el.scrollable ?? false,
    checkable: el.checkable ?? false,
    checked: el.checked ?? false,
    focused: el.isFocused ?? false,
    visible: el.isVisible ?? true,
    left: r ? r.left : 0,
    top: r ? r.top : 0,
    width: r ? r.width : 0,
    height: r ? r.height : 0
  };
}

async function walk(el: AccessibilityElement, depth: number, snap: ScreenSnapshot): Promise<void> {
  if (snap.nodes.length >= MAX_RAW_NODES || depth > MAX_DEPTH) {
    return;
  }
  snap.nodes.push(toNode(el));
  snap.elements.push(el);
  let children: AccessibilityElement[] = [];
  try {
    children = await el.getChildren();
  } catch (e) {
    return;
  }
  for (const child of children) {
    await walk(child, depth + 1, snap);
  }
}

export async function readScreen(ctx: AccessibilityExtensionContext): Promise<ScreenSnapshot> {
  const root = await ctx.getRootInActiveWindow();
  const snap: ScreenSnapshot = { bundleName: str(root.bundleName), nodes: [], elements: [] };
  await walk(root, 0, snap);
  return snap;
}

/**
 * Clicks the element; if it is not clickable itself (e.g. a Text inside a
 * Button), walks up to the nearest clickable ancestor.
 */
export async function clickElement(el: AccessibilityElement): Promise<void> {
  let target: AccessibilityElement = el;
  for (let i = 0; i < 4 && !(target.clickable ?? false); i++) {
    try {
      target = await target.getParent();
    } catch (e) {
      target = el;
      break;
    }
  }
  await target.executeAction(AccessibilityAction.CLICK);
}

/** Scrolls the element, or its nearest scrollable ancestor. */
export async function scrollElement(el: AccessibilityElement, forward: boolean): Promise<void> {
  let target: AccessibilityElement = el;
  for (let i = 0; i < 6 && !(target.scrollable ?? false); i++) {
    try {
      target = await target.getParent();
    } catch (e) {
      throw new Error('Element is not inside a scrollable container');
    }
  }
  await target.executeAction(forward ? AccessibilityAction.SCROLL_FORWARD : AccessibilityAction.SCROLL_BACKWARD);
}

export async function setElementText(el: AccessibilityElement, text: string): Promise<void> {
  const param: Parameter = { setText: text };
  await el.executeAction(AccessibilityAction.SET_TEXT, param);
}

export async function globalAction(ctx: AccessibilityExtensionContext,
  action: AccessibilityAction): Promise<void> {
  const root = await ctx.getRootInActiveWindow();
  await root.executeAction(action);
}
