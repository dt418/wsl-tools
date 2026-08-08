#!/usr/bin/env node
/**
 * Documentation validator.
 *
 * For every Markdown file in the repository, checks:
 *   1. Code fences are balanced.
 *   2. Every ```mermaid block parses as a valid Mermaid diagram.
 *   3. Every internal Markdown link resolves to an existing file.
 *
 * Usage: npm run validate:docs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { JSDOM } from "jsdom";

// mermaid's sanitizer (DOMPurify) requires a DOM in Node.js.
// Set up jsdom globals before importing mermaid.
const dom = new JSDOM("<!doctype html><html><body></body></html>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
Object.defineProperty(globalThis, "navigator", {
  value: dom.window.navigator,
  configurable: true,
});

const { default: mermaid } = await import("mermaid");

mermaid.initialize({ startOnLoad: false, securityLevel: "loose" });

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ignoredDirs = new Set([
  "node_modules",
  ".git",
  ".idea",
  ".vscode",
  "dist",
  "build",
  "target",
]);

function collectMarkdown(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!ignoredDirs.has(entry.name)) {
        collectMarkdown(path.join(dir, entry.name), acc);
      }
    } else if (entry.name.endsWith(".md")) {
      acc.push(path.join(dir, entry.name));
    }
  }
  return acc;
}

// When invoked by lint-staged, positional arguments are the staged files
// (absolute paths). Without arguments, every Markdown file is validated.
const fileArgs = process.argv.slice(2);
const files = (
  fileArgs.length > 0
    ? fileArgs
        .map((arg) => path.resolve(arg))
        .filter((file) => file.endsWith(".md") && fs.existsSync(file))
    : collectMarkdown(root)
).sort();
let totalMermaid = 0;
let failedFiles = 0;

for (const file of files) {
  const rel = path.relative(root, file);
  const text = fs.readFileSync(file, "utf8");
  const problems = [];

  // 1. Fence balance
  const fences = (text.match(/^```/gm) || []).length;
  if (fences % 2 !== 0) {
    problems.push(`unbalanced code fences (${fences} fence markers)`);
  }

  // 2. Mermaid blocks
  const blocks = [...text.matchAll(/```mermaid[ \t]*\n([\s\S]*?)```/g)];
  for (let i = 0; i < blocks.length; i++) {
    totalMermaid++;
    try {
      await mermaid.parse(blocks[i][1]);
    } catch (err) {
      const msg = String(err?.message ?? err)
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 240);
      problems.push(`mermaid block ${i + 1} failed: ${msg}`);
    }
  }

  // 3. Internal links
  const links = [...text.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)].map((m) => m[1]);
  for (const target of links) {
    if (/^(https?:|mailto:|#)/.test(target)) continue;
    const resolved = path.resolve(path.dirname(file), target.split("#")[0]);
    if (!fs.existsSync(resolved)) {
      problems.push(`broken link "${target}" (resolves to ${resolved})`);
    }
  }

  if (problems.length > 0) {
    failedFiles++;
    console.error(`[FAIL] ${rel}`);
    for (const p of problems) {
      console.error(`  - ${p}`);
    }
  } else {
    const extra = blocks.length > 0 ? `, mermaid=${blocks.length}` : "";
    console.log(`[OK]   ${rel} (fences balanced${extra})`);
  }
}

console.log("");
console.log(`Mermaid diagrams validated: ${totalMermaid}`);

if (failedFiles > 0) {
  console.error(`FAILED: ${failedFiles} file(s) have issues.`);
  process.exit(1);
}

console.log("All documentation checks passed.");
