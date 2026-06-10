import { raycastApp } from "./raycast";
import { LatticeApp } from "./types";

const apps = [raycastApp] as const satisfies readonly LatticeApp[];

export function listApps(): readonly LatticeApp[] {
  return apps;
}

export function getApp(id: string): LatticeApp {
  const app = apps.find((candidate) => candidate.id === id);
  if (!app) {
    throw new Error(`Unknown app: ${id}`);
  }

  return app;
}
