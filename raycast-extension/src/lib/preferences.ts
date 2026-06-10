import { getPreferenceValues } from "@raycast/api";

export interface Preferences {
  projectPath: string;
  vaultPath: string;
  bunPath: string;
}

export function getPreferences(): Preferences {
  return getPreferenceValues<Preferences>();
}
