/**
 * Commit message linting rules.
 *
 * Uses the Conventional Commits specification:
 *   <type>[optional scope]: <description>
 *
 * Examples:
 *   feat: add backup-only mode
 *   fix(safety): block unregister when archive is missing
 *   docs(vi): translate safety model
 *   chore: bump validation toolchain
 */
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // Project docs are bilingual; keep the subject line short.
    "header-max-length": [2, "always", 100],
  },
};
