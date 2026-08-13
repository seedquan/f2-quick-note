#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, lstatSync, readFileSync } from "node:fs";
import { basename, resolve, sep } from "node:path";

const ROOT = resolve(import.meta.dirname, "..");
const MAX_TEXT_BYTES = 2 * 1024 * 1024;
const findings = [];
const findingKeys = new Set();

function git(args, encoding = "utf8") {
  return execFileSync("git", ["-C", ROOT, ...args], {
    encoding,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function report(path, type) {
  const key = `${path}\0${type}`;
  if (findingKeys.has(key)) return;
  findingKeys.add(key);
  findings.push({ path, type });
}

function sensitivePath(path) {
  const lower = path.toLowerCase();
  const name = basename(lower);
  return name === ".env" || name.startsWith(".env.")
    || /\.(pem|key|p12|pfx)$/.test(name)
    || lower.split("/").includes("secrets")
    || lower.startsWith(".ssh/") || lower.includes("/.ssh/")
    || /(^|\/)(id_rsa|id_dsa|id_ecdsa|id_ed25519)(\.pub)?$/.test(lower);
}

function privateContentPath(path) {
  return /(^|\/)(?:captures|exports|screenshots|clipboard-data|notes-data|\.build|dist)(?:\/|$)/i.test(path);
}

const checks = [
  [/@microsoft\.com\b/i, "company email identity"],
  [/\bxiquan_microsoft\b/i, "enterprise GitHub identity"],
  [/(?:^|[^\w])\/(?:Users|home)\/[^/\s]+\//m, "absolute home path"],
  [/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/, "private key material"],
  [/\bAKIA[0-9A-Z]{16}\b/, "cloud access key pattern"],
  [/\b(?:ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}\b/, "GitHub credential pattern"],
  [/\b(?:api[_-]?key|access[_-]?token|secret|password)\s*[:=]\s*["'][^"'\n]{12,}["']/i, "credential assignment pattern"],
];

function scanText(path, text, scope) {
  for (const [pattern, type] of checks) if (pattern.test(text)) report(path, `${scope}: ${type}`);
  const emails = text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi) ?? [];
  if (emails.some(email => !/(?:users\.noreply\.github\.com|example\.(?:com|org|net))$/i.test(email))) {
    report(path, `${scope}: personal/contact email address`);
  }
}

function scanBlob(path, mode, object, scope) {
  if (sensitivePath(path)) {
    report(path, `${scope}: sensitive filename (content deliberately not read)`);
    return;
  }
  if (privateContentPath(path)) {
    report(path, `${scope}: private/generated content location`);
    return;
  }
  if (mode === "120000") {
    report(path, `${scope}: symbolic link`);
    return;
  }
  const size = Number(git(["cat-file", "-s", object]));
  if (!Number.isSafeInteger(size) || size > MAX_TEXT_BYTES) return;
  const buffer = git(["cat-file", "blob", object], "buffer");
  if (!buffer.includes(0)) scanText(path, buffer.toString("utf8"), scope);
}

const tracked = git(["ls-files", "-z"], "buffer").toString("utf8").split("\0").filter(Boolean);
const ownedNewFiles = [
  ".githooks/pre-commit", ".githooks/pre-push", ".github/workflows/ci.yml",
  "Resources/F2QuickNote.entitlements",
  "Sources/F2QuickNote/AppleNotesSearchController.swift",
  "Sources/F2QuickNoteCore/PrivateTemporaryStorage.swift",
  "scripts/privacy-check.mjs", "scripts/privacy-git-hook.mjs", "scripts/release-privacy-check.mjs",
];
const currentFiles = [...new Set([...tracked, ...ownedNewFiles.filter(path => existsSync(resolve(ROOT, path)))])].sort();
for (const path of currentFiles) {
  if (sensitivePath(path)) {
    report(path, "current tree: sensitive filename (content deliberately not read)");
    continue;
  }
  if (privateContentPath(path)) {
    report(path, "current tree: private/generated content location");
    continue;
  }
  if (path === "scripts/privacy-check.mjs") continue;
  const absolute = resolve(ROOT, path);
  if (absolute !== ROOT && !absolute.startsWith(`${ROOT}${sep}`)) {
    report(path, "current tree: path escapes repository");
    continue;
  }
  const stat = lstatSync(absolute);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    report(path, "current tree: non-regular file or symbolic link");
    continue;
  }
  if (stat.size > MAX_TEXT_BYTES) continue;
  const buffer = readFileSync(absolute);
  if (!buffer.includes(0)) scanText(path, buffer.toString("utf8"), "current tree");
}

for (const record of git(["ls-files", "--stage", "-z"], "buffer").toString("utf8").split("\0").filter(Boolean)) {
  const tab = record.indexOf("\t");
  if (tab === -1) continue;
  const [mode, object, stage] = record.slice(0, tab).split(" ");
  const path = record.slice(tab + 1);
  if (stage !== "0") report(path, "Git index: unresolved merge entry");
  else scanBlob(path, mode, object, "Git index");
}

const commits = git(["rev-list", "--all"]).split(/\r?\n/).filter(Boolean);
const historical = new Set();
for (const commit of commits) {
  const tree = git(["ls-tree", "-rz", "--full-tree", commit], "buffer").toString("utf8");
  for (const record of tree.split("\0").filter(Boolean)) {
    const tab = record.indexOf("\t");
    if (tab === -1) continue;
    const [mode, type, object] = record.slice(0, tab).split(" ");
    const path = record.slice(tab + 1);
    if (type !== "blob") continue;
    const identity = `${object}\0${path}`;
    if (historical.has(identity)) continue;
    historical.add(identity);
    scanBlob(path, mode, object, "history");
  }
}

const identities = git(["log", "--all", "--format=%ae%n%ce"]);
const companyIdentityCount = identities.split(/\r?\n/).filter(value => /@microsoft\.com$/i.test(value.trim())).length;
if (companyIdentityCount) report("Git history", `company author/committer identities (${companyIdentityCount} occurrences)`);

const ignore = readFileSync(resolve(ROOT, ".gitignore"), "utf8").split(/\r?\n/);
for (const required of [".env", ".env.*", "secrets/", "captures/", "exports/", "screenshots/"]) {
  if (!ignore.includes(required)) report(".gitignore", `missing privacy exclusion: ${required}`);
}

for (const hook of [".githooks/pre-commit", ".githooks/pre-push"]) {
  const absolute = resolve(ROOT, hook);
  if (!existsSync(absolute)) report(hook, "privacy hook missing");
  else if ((lstatSync(absolute).mode & 0o111) === 0) report(hook, "privacy hook is not executable");
}

const noteCapture = readFileSync(resolve(ROOT, "Sources/F2QuickNote/NoteCapture.swift"), "utf8");
const appDelegate = readFileSync(resolve(ROOT, "Sources/F2QuickNote/AppDelegate.swift"), "utf8");
const main = readFileSync(resolve(ROOT, "Sources/F2QuickNote/main.swift"), "utf8");
const allSource = currentFiles
  .filter(path => path.startsWith("Sources/") || path.startsWith("Resources/"))
  .map(path => readFileSync(resolve(ROOT, path), "utf8")).join("\n");
if (/\b(?:URLSession|NWConnection|import\s+Network|CFStreamCreatePairWithSocketToHost)\b/.test(allSource)) {
  report("Sources/", "network client API present in clipboard application");
}
for (const invariant of ["0o600", "cleanUpTemporaryFiles", "isSymbolicLinkKey", "maximumAttachmentCount"]) {
  if (!noteCapture.includes(invariant)) report("Sources/F2QuickNote/NoteCapture.swift", `missing privacy invariant: ${invariant}`);
}
if (!allSource.includes("0o700")) report("Sources/F2QuickNoteCore/PrivateTemporaryStorage.swift", "missing private directory permissions");
if (appDelegate.includes("confirmAttachmentCapture")) report("Sources/F2QuickNote/AppDelegate.swift", "attachment capture must not require confirmation");
if (!main.includes("--allow-content") || !main.includes("--allow-attachments")) report("Sources/F2QuickNote/main.swift", "CLI content consent flags missing");
const makefile = readFileSync(resolve(ROOT, "Makefile"), "utf8");
if (!makefile.includes("override INSTALLED_APP := /Applications/F2QuickNote.app") || !makefile.includes("guard-paths")) {
  report("Makefile", "build/install deletion scope is not fixed and guarded");
}
if (!makefile.includes("release-privacy-check.mjs")) report("Makefile", "release privacy gate missing");
if (!makefile.includes("--options runtime") || !makefile.includes("--entitlements Resources/F2QuickNote.entitlements")) {
  report("Makefile", "Hardened Runtime or entitlement signing missing");
}
const entitlements = readFileSync(resolve(ROOT, "Resources/F2QuickNote.entitlements"), "utf8");
for (const required of [
  "com.apple.security.automation.apple-events",
  "com.apple.security.files.user-selected.read-only",
  "com.apple.security.temporary-exception.apple-events",
  "com.apple.Notes",
]) {
  if (!entitlements.includes(required)) report("Resources/F2QuickNote.entitlements", `missing entitlement boundary: ${required}`);
}
if (entitlements.includes("com.apple.security.app-sandbox")) {
  report("Resources/F2QuickNote.entitlements", "App Sandbox blocks the Accessibility API required by Command-F2");
}
if (/com\.apple\.security\.network\.(?:client|server)/.test(entitlements)) {
  report("Resources/F2QuickNote.entitlements", "network entitlement is forbidden");
}
if (/NSLog\([^\n]*(?:payload|clipboard|attachmentPaths|attachmentURLs|bodyHTML|source)/i.test(allSource)) {
  report("Sources/", "possible clipboard or path logging");
}

if (findings.length) {
  console.error(`Privacy check failed with ${findings.length} finding(s):`);
  for (const finding of findings) console.error(`- ${finding.path}: ${finding.type}`);
  process.exit(1);
}
console.log(`Privacy check passed (${currentFiles.length} current files; ${commits.length} history commits checked).`);
