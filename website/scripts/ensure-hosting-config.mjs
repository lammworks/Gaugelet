import { mkdirSync, existsSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// `.openai/hosting.json` carries a deployment-specific project id, so the real
// file is untracked. The Sites build plugin still expects it to exist, so a
// binding-free stub is generated for clean checkouts such as CI.
const websiteRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const configPath = resolve(websiteRoot, ".openai/hosting.json");

if (existsSync(configPath)) {
  process.exit(0);
}

mkdirSync(dirname(configPath), { recursive: true });
writeFileSync(
  configPath,
  `${JSON.stringify({ project_id: null, d1: null, r2: null }, null, 2)}\n`,
);
console.log("Generated a binding-free .openai/hosting.json stub.");
