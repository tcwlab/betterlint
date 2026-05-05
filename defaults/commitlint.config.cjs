// betterlint default commitlint config — used when consumer repo has no own
// commitlint config. Mirrors the betterlint repo's own .commitlintrc.json
// (Conventional Commits 1.0, header-max-length 100, no body/footer line caps,
// case-insensitive subjects).
//
// Module resolution: this file is loaded via `commitlint --config <path>`. Node
// resolves `extends` relative to the config file's directory. The Dockerfile
// symlinks /etc/betterlint/defaults/node_modules → /usr/local/lib/node_modules
// so that `@commitlint/config-conventional` (npm-global-installed) resolves
// from this location without further hints.
module.exports = {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "subject-case": [0],
    "header-max-length": [2, "always", 100],
    "body-max-line-length": [0],
    "footer-max-line-length": [0],
  },
};
