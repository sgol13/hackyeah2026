/**
 * User settings (AI provider, model, reasoning effort, one API key per provider,
 * floating orb switch) in app-private Preferences. The UI, the overlay and the
 * accessibility-extension process all read the same store; the other processes
 * drop their in-memory cache first so they always see the latest saved values.
 * A key never leaves the app sandbox except in the HTTPS request to its own provider.
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { PROVIDER_ANTHROPIC, PROVIDERS } from '../agent/Providers';
import { parseSkills, serializeSkills, UserSkill } from '../agent/Skills';

const STORE = 'settings';
const KEY_PROVIDER = 'provider';
const KEY_MODEL = 'model';
const KEY_EFFORT = 'effort';
const KEY_SKILLS = 'skills';
const KEY_API_KEY_PREFIX = 'apiKey.';
/** single key of versions that only supported Anthropic */
const LEGACY_KEY_API_KEY = 'apiKey';

export interface AgentSettings {
  provider: string;
  model: string;
  /** API key of `provider` */
  apiKey: string;
  /** reasoning effort; '' = the model's default */
  effort: string;
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
    apiKey: apiKeyFrom(prefs, provider),
    effort: prefs.getSync(KEY_EFFORT, '') as string
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
  prefs.putSync(KEY_EFFORT, settings.effort);
  prefs.putSync(KEY_API_KEY_PREFIX + settings.provider, settings.apiKey.trim());
  await prefs.flush();
}

export function loadSkills(ctx: Context, dropCache: boolean = false): UserSkill[] {
  const json = store(ctx, dropCache).getSync(KEY_SKILLS, '[]');
  return typeof json === 'string' ? parseSkills(json as string) : [];
}

export async function saveSkills(ctx: Context, skills: UserSkill[]): Promise<void> {
  const prefs = store(ctx, false);
  prefs.putSync(KEY_SKILLS, serializeSkills(skills));
  await prefs.flush();
}

const KEY_SHOW_ORB = 'showOrb';

/** AppStorage key: true while the agent service is enabled (written by Index, shown in Settings). */
export const KEY_SERVICE_READY = 'serviceReady';
/** ServiceExtensionAbility that owns the floating orb, sheet and pill. */
export const OVERLAY_ABILITY = 'OverlayService';

/** Whether the floating orb is shown over other apps (default on). */
export function loadShowOrb(ctx: Context): boolean {
  return store(ctx, false).getSync(KEY_SHOW_ORB, true) as boolean;
}

export async function saveShowOrb(ctx: Context, on: boolean): Promise<void> {
  const prefs = store(ctx, false);
  prefs.putSync(KEY_SHOW_ORB, on);
  await prefs.flush();
}
