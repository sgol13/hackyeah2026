/** What is missing before a task can start ('' = ready). Shown in the app and in the overlay sheet. */
import { isValidModelId } from '../agent/Providers';

export function checkRun(providerLabel: string, apiKey: string, model: string, task: string): string {
  if (apiKey.trim().length === 0) {
    return `Add your ${providerLabel} API key in Settings.`;
  }
  if (!isValidModelId(model)) {
    return 'Choose a model in Settings. A custom model ID may use letters, digits and . _ - : /';
  }
  if (task.trim().length === 0) {
    return 'Describe what the agent should do.';
  }
  return '';
}
