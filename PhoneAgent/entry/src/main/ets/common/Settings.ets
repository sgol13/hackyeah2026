/**
 * User settings (AI provider, model, one API key per provider) in app-private
 * Preferences. Both the UI process and the accessibility-extension process read
 * the same store; the extension drops its in-memory cache first so it always sees
 * the latest saved values. A key never leaves the app sandbox except in the HTTPS
 * request to its own provider.
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PROVIDER_ANTHROPIC, PROVIDERS } from '../agent/Providers';

const STORE = 'settings';
const KEY_PROVIDER = 'provider';
const KEY_MODEL = 'model';
const KEY_API_KEY_PREFIX = 'apiKey.';
/** single key of versions that only supported Anthropic */
const LEGACY_KEY_API_KEY = 'apiKey';

export interface AgentSettings {
  provider: string;
  model: string;
  /** API key of `provider` */
  apiKey: string;
}

function store(ctx: Context, dropCache: boolean): preferences.Preferences {
  if (dropCache) {
    preferences.removePreferencesFromCacheSync(ctx, { name: STORE });
  }
  return preferences.getPreferencesSync(ctx, { name: STORE });
}

function apiKeyFrom(prefs: preferences.Preferences, provider: string): string {
  const key = prefs.getSync(KEY_API_KEY_PREFIX + provider, '') as string;
  if (key.length === 0 && provider === PROVIDER_ANTHROPIC) {
    return prefs.getSync(LEGACY_KEY_API_KEY, '') as string;
  }
  return key;
}

export function loadSettings(ctx: Context, dropCache: boolean): AgentSettings {
  const prefs = store(ctx, dropCache);
  const provider = prefs.getSync(KEY_PROVIDER, PROVIDER_ANTHROPIC) as string;
  return {
    provider: provider,
    model: prefs.getSync(KEY_MODEL, PROVIDERS[0].models[0].id) as string,
    apiKey: apiKeyFrom(prefs, provider)
  };
}

export function loadApiKey(ctx: Context, provider: string, dropCache: boolean): string {
  return apiKeyFrom(store(ctx, dropCache), provider);
}

export async function saveApiKey(ctx: Context, provider: string, apiKey: string): Promise<void> {
  const prefs = store(ctx, false);
  prefs.putSync(KEY_API_KEY_PREFIX + provider, apiKey.trim());
  await prefs.flush();
}

export async function saveSettings(ctx: Context, settings: AgentSettings): Promise<void> {
  const prefs = store(ctx, false);
  prefs.putSync(KEY_PROVIDER, settings.provider);
  prefs.putSync(KEY_MODEL, settings.model);
  prefs.putSync(KEY_API_KEY_PREFIX + settings.provider, settings.apiKey.trim());
  await prefs.flush();
}
