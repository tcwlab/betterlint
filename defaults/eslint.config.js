// betterlint baked-in eslint default — applied when the consumer repo ships
// no own eslint config. Mirrors the standard "eslint v9 flat-config + recommended
// rules + browser/node/es2024 globals" baseline. Consumer configs always win.
//
// Resolution: the wrapper invokes eslint with --config /etc/betterlint/defaults/eslint.config.js.
// The Dockerfile symlinks /etc/betterlint/defaults/node_modules → /usr/local/lib/node_modules
// so the imports below resolve against the globally-installed @eslint/js and globals.
import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.es2024,
      },
    },
  },
];
