export interface AppInstallOptions {
  appId: string;
  vaultPath: string;
  version?: string;
  repo?: string;
  baseUrl?: string;
  sourceDir?: string;
  installDir?: string;
  latticePath?: string;
  configPath?: string;
  importToRaycast?: boolean;
}

export interface AppInstallResult {
  app: string;
  installed_path: string;
  config_path: string;
  steps: string[];
  warnings: string[];
}

export interface AppDoctorOptions {
  appId: string;
  configPath?: string;
}

export interface AppDoctorResult {
  app: string;
  ok: string[];
  warnings: string[];
  errors: string[];
}

export interface LatticeApp {
  id: string;
  title: string;
  description: string;
  install(options: AppInstallOptions): Promise<AppInstallResult>;
  doctor(options: AppDoctorOptions): Promise<AppDoctorResult>;
}
