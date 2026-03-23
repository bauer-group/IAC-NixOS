## [1.1.3](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.2...v1.1.3) (2026-03-23)

### 🐛 Bug Fixes

* **networking:** fixed DHCP configuration module precedence ([8aacd64](https://github.com/bauer-group/IAC-NixOS/commit/8aacd64d6027ccd9a1efcc0993efaa6bd88274fe))

## [1.1.2](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.1...v1.1.2) (2026-03-23)

### ♻️ Refactoring

* **embedded-dev:** made feature conditional ([6b7c90f](https://github.com/bauer-group/IAC-NixOS/commit/6b7c90fb94849b8d094961a78c951afabb16fe42))

## [1.1.1](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.0...v1.1.1) (2026-03-23)

### 🐛 Bug Fixes

- **ci:** changed nix fmt check flag to CI mode ([ac9e649](https://github.com/bauer-group/IAC-NixOS/commit/ac9e649e9ad7c27f996d291c0ead9fbc05f9711e))
- **ci:** exclude workflow files from formatting ([aa726e9](https://github.com/bauer-group/IAC-NixOS/commit/aa726e9b25c6a5814619b599bc427aa02ebcf112))

## [1.1.0](https://github.com/bauer-group/IAC-NixOS/compare/v1.0.0...v1.1.0) (2026-03-22)

### 🚀 Features

- **ci:** add template builds with CI fallback support ([d4326ee](https://github.com/bauer-group/IAC-NixOS/commit/d4326ee22eff17048decd58fe9f16cbee6d04a81))

### ♻️ Refactoring

- **infra:** migrated to template-based config ([d542cca](https://github.com/bauer-group/IAC-NixOS/commit/d542cca70b6ba36cc574c7c336b2692b2aed7de0))

## [1.0.0](https://github.com/bauer-group/IAC-NixOS/compare/v0.1.0...v1.0.0) (2026-03-22)

### ⚠ BREAKING CHANGES

- **flake:** Existing deployments must migrate to parameter-based
  system. Per-host hardcoded configs no longer supported.

### ♻️ Refactoring

- **flake:** switched to parametric template-based architecture ([018481b](https://github.com/bauer-group/IAC-NixOS/commit/018481bb7071f6a19fe948f8f670657224edab7d))

## [0.1.0](https://github.com/bauer-group/IAC-NixOS/compare/v0.0.0...v0.1.0) (2026-03-21)

### 🚀 Features

- Initial Commit ([1123c82](https://github.com/bauer-group/IAC-NixOS/commit/1123c8221dd8f310ae6cc408b9d4f491e909f8dd))
