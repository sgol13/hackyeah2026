/**
 * User settings (API key, model) in app-private Preferences. Both the UI process
 * and the accessibility-extension process read the same store; the extension
 * drops its in-memory cache first so it always sees the latest saved values.
 * The key never leaves the app sandbox except in the HTTPS request to Anthropic.
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { MODELS } from '../agent/Anthropic';

const STORE = 'settings';
const KEY_API_KEY = 'apiKey';
const KEY_MODEL = 'model';

export interface AgentSettings {
  apiKey: string;
  model: string;
}

export function loadSettings(ctx: Context, dropCache: boolean): AgentSettings {
  if (dropCache) {
    preferences.removePreferencesFromCacheSync(ctx, { name: STORE });
  }
  const store = preferences.getPreferencesSync(ctx, { name: STORE });
  return {
    apiKey: store.getSync(KEY_API_KEY, '') as string,
    model: store.getSync(KEY_MODEL, MODELS[0].id) as string
  };
}

export async function saveSettings(ctx: Context, settings: AgentSettings): Promise<void> {
  const store = preferences.getPreferencesSync(ctx, { name: STORE });
  store.putSync(KEY_API_KEY, settings.apiKey.trim());
  store.putSync(KEY_MODEL, settings.model);
  await store.flush();
}
