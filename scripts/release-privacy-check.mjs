#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { basename, relative, resolve, sep } from "node:path";

const ROOT = realpathSync(resolve(import.meta.dirname, ".."));
const input = process.argv[2];
if (!input) {
  console.error("Usage: release-privacy-check <binary-or-app-bundle>");
  process.exit(1);
}

const candidate = resolve(input);
if (!existsSync(candidate) || lstatSync(candidate).isSymbolicLink()) {
  console.error("Release privacy check failed: missing or symbolic-link artifact");
  process.exit(1);
}

const allowedBundleFiles = new Set([
  "Contents/Info.plist",
  "Contents/MacOS/F2QuickNote",
  "Contents/Resources/F2QuickNote.icns",
  "Contents/_CodeSignature/CodeResources",
]);
const binaries = [];

function visit(path, bundleRoot = null) {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink()) throw new Error("symbolic link in release artifact");
  if (stat.isDirectory()) {
    for (const entry of readdirSync(path)) visit(resolve(path, entry), bundleRoot ?? path);
    return;
  }
  if (!stat.isFile()) throw new Error("non-regular release artifact");
  if (bundleRoot) {
    const name = relative(bundleRoot, path).split(sep).join("/");
    if (!allowedBundleFiles.has(name)) throw new Error(`unexpected bundle file: ${name}`);
  }
  if (basename(path) === "F2QuickNote") binaries.push(path);
}

try {
  if (lstatSync(candidate).isDirectory()) visit(candidate, candidate);
  else binaries.push(candidate);
  if (binaries.length !== 1) throw new Error("release must contain exactly one executable");

  if (lstatSync(candidate).isDirectory()) {
    const signature = spawnSync("codesign", ["--display", "--requirements", "-", candidate], {
      encoding: "utf8",
      env: Object.fromEntries(["LANG", "LC_ALL", "PATH"].filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]])),
      stdio: ["ignore", "pipe", "pipe"],
    });
    if (signature.status !== 0) throw new Error("app bundle has no valid code signature");
    if (/designated\s*=>\s*cdhash\b/.test(`${signature.stdout}\n${signature.stderr}`)) {
      throw new Error("ad-hoc signature cannot preserve macOS privacy permissions across builds");
    }
  }

  const plist = lstatSync(candidate).isDirectory() ? resolve(candidate, "Contents", "Info.plist") : null;
  const outputs = [];
  for (const binary of binaries) {
    const result = spawnSync("strings", [binary], {
      encoding: "utf8",
      env: Object.fromEntries(["LANG", "LC_ALL", "PATH"].filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]])),
      stdio: ["ignore", "pipe", "ignore"],
      maxBuffer: 32 * 1024 * 1024,
    });
    if (result.status !== 0) throw new Error("could not inspect release executable");
    outputs.push(result.stdout);
  }
  if (plist) outputs.push(readFileSync(plist, "utf8"));
  const text = outputs.join("\n");
  const risks = [
    [/(?:^|[^\w])\/(?:Users|home)\/[^/\s]+\//m, "absolute home path"],
    [/@microsoft\.com\b/i, "company identity"],
    [/\bxiquan_microsoft\b/i, "enterprise GitHub identity"],
    [/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, "email address"],
    [/(?:captures|exports|screenshots|clipboard-data|notes-data)\//i, "private content path"],
  ].filter(([pattern]) => pattern.test(text)).map(([, type]) => type);
  if (risks.length) throw new Error(`embedded privacy risk type(s): ${risks.join(", ")}`);
  console.log("Release privacy check passed (allowlisted files only; no identity/content-path patterns).")
} catch (error) {
  console.error(`Release privacy check failed: ${error.message}`);
  process.exit(1);
}
