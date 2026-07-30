#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const checker = resolve(ROOT, "scripts", "privacy-check.mjs");
const mode = process.argv[2];

function runCheck() {
  return spawnSync(process.execPath, [checker], { cwd: ROOT, stdio: "inherit" }).status === 0;
}

if (mode === "pre-commit") {
  try {
    execFileSync("git", ["-C", ROOT, "symbolic-ref", "--quiet", "HEAD"], { stdio: "ignore" });
  } catch {
    console.error("Privacy check requires a named branch");
    process.exit(1);
  }
  process.exit(runCheck() ? 0 : 1);
}

if (mode === "pre-push") {
  const updates = readFileSync(0, "utf8").split(/\r?\n/).filter(Boolean);
  if (updates.some(line => !/^(?:refs\/(?:heads|tags)\/[A-Za-z0-9._/-]+) [0-9a-f]{40} (?:refs\/(?:heads|tags)\/[A-Za-z0-9._/-]+) [0-9a-f]{40}$/.test(line))) {
    console.error("Privacy check refused malformed push metadata");
    process.exit(1);
  }
  process.exit(runCheck() ? 0 : 1);
}

console.error("Unknown privacy hook mode");
process.exit(1);
