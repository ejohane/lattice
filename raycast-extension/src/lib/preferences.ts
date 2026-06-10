import { getPreferenceValues } from "@raycast/api";

export interface Preferences {
  latticePath?: string;
  vaultPath?: string;
}

export function getPreferences(): Preferences {
  return getPreferenceValues<Preferences>();
}
