#!/usr/bin/env node
/**
 * Verifies that English and Vietnamese documentation pairs stay in sync.
 *
 * Rules:
 *   - Every official English Markdown file must have a matching `*.vi.md`.
 *   - Every `*.vi.md` must have a matching English counterpart.
 *   - Shared top-level headings (## / ###) should appear in both languages
 *     in the same order (IDs are language-agnostic by position).
 *
 * Usage: npm run check:docs-sync
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

// English canonical docs and their expected Vietnamese counterparts.
const pairs = [
  ["README.md", "README.vi.md"],
  ["CHANGELOG.md", "CHANGELOG.vi.md"],
  ["CONTRIBUTING.md", "CONTRIBUTING.vi.md"],
  ["SECURITY.md", "SECURITY.vi.md"],
  ["CODE_OF_CONDUCT.md", "CODE_OF_CONDUCT.vi.md"],
  ["docs/SAFETY_MODEL.md", "docs/SAFETY_MODEL.vi.md"],
];

function read(rel) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) {
    return null;
  }
  return fs.readFileSync(abs, "utf8");
}

function headingLevels(text) {
  // Collect ## and ### headings only (ignore H1 title which is language-specific).
  return (text.match(/^#{2,3}\s+.+$/gm) || []).map((line) => {
    const match = line.match(/^(#{2,3})\s+/);
    return match[1].length;
  });
}

let failed = false;

for (const [en, vi] of pairs) {
  const enText = read(en);
  const viText = read(vi);

  if (!enText) {
    console.error(`[FAIL] missing English doc: ${en}`);
    failed = true;
    continue;
  }

  if (!viText) {
    console.error(`[FAIL] missing Vietnamese pair for ${en} (expected ${vi})`);
    failed = true;
    continue;
  }

  const enLevels = headingLevels(enText);
  const viLevels = headingLevels(viText);

  if (enLevels.length !== viLevels.length) {
    console.error(
      `[FAIL] heading count mismatch: ${en} has ${enLevels.length} H2/H3, ` +
        `${vi} has ${viLevels.length}`
    );
    failed = true;
    continue;
  }

  for (let i = 0; i < enLevels.length; i++) {
    if (enLevels[i] !== viLevels[i]) {
      console.error(
        `[FAIL] heading level mismatch at position ${i + 1}: ` +
          `${en}=H${enLevels[i]}, ${vi}=H${viLevels[i]}`
      );
      failed = true;
      break;
    }
  }

  if (!failed) {
    console.log(`[OK]   ${en} <-> ${vi} (H2/H3 structure aligned, ${enLevels.length} sections)`);
  } else {
    // Continue reporting remaining pairs even after a failure.
  }
}

// Detect orphan Vietnamese files that are not in the pair list.
function collectVi(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!["node_modules", ".git", ".lefthook", ".husky"].includes(entry.name)) {
        collectVi(path.join(dir, entry.name), acc);
      }
    } else if (entry.name.endsWith(".vi.md")) {
      acc.push(path.relative(root, path.join(dir, entry.name)).replaceAll("\\", "/"));
    }
  }
  return acc;
}

const expectedVi = new Set(pairs.map(([, vi]) => vi));
for (const found of collectVi(root)) {
  if (!expectedVi.has(found)) {
    console.error(`[FAIL] unexpected Vietnamese doc without pair mapping: ${found}`);
    failed = true;
  }
}

if (failed) {
  console.error("");
  console.error("Documentation sync check failed.");
  process.exit(1);
}

console.log("");
console.log("All English / Vietnamese documentation pairs are in sync.");
