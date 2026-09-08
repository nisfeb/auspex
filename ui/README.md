# React + TypeScript + Vite

## Running against a ship

`npm run dev` proxies to `http://localhost:8081` (`~wex`) by default. Point it
at a different ship's HTTP port with `SHIP_URL`, e.g.
`SHIP_URL=http://localhost:8080 npm run dev` for `~feb`.

Separately, `src/api.ts` sets `api.ship` from `VITE_SHIP`, which **defaults
to `'wex'`** when unset. There is no `.env` file, so this default is silent:
if you point `SHIP_URL` at a different ship and forget `VITE_SHIP`, the app
still authenticates as `~wex` against the wrong ship's channel and nothing
will look obviously wrong until pokes and scries fail. Set both together,
e.g. `SHIP_URL=http://localhost:8080 VITE_SHIP=feb npm run dev`.

This template provides a minimal setup to get React working in Vite with HMR and some Oxlint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the Oxlint configuration

If you are developing a production application, we recommend enabling type-aware lint rules by installing `oxlint-tsgolint` and editing `.oxlintrc.json`:

```json
{
  "$schema": "./node_modules/oxlint/configuration_schema.json",
  "plugins": ["react", "typescript", "oxc"],
  "options": {
    "typeAware": true
  },
  "rules": {
    "react/rules-of-hooks": "error",
    "react/only-export-components": ["warn", { "allowConstantExport": true }]
  }
}
```

See the [Oxlint rules documentation](https://oxc.rs/docs/guide/usage/linter/rules) for the full list of rules and categories.
