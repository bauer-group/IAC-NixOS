# Changelog

All notable changes to this project are documented here. This file is maintained
automatically by [semantic-release](https://github.com/semantic-release/semantic-release)
on every release to `main`.

## [4.0.0](https://github.com/bauer-group/IAC-NixOS/compare/v3.1.0...v4.0.0) (2026-09-16)

### ⚠ BREAKING CHANGES

* **monitoring:** a monitoring server with bauergroup.services.monitoring.enable
  now requires grafanaAdminPasswordFile and is reachable on localhost only;
  set grafanaListenAddress to expose it. Hosts scraped remotely need the
  monitoring server's address in nodeExporterAllowedSources, otherwise
  port 9100 stays closed.
* **kiosk:** the kiosk browser now runs as bauergroup.params.kiosk.user
  (default "kiosk") instead of the admin account. Machines whose admin is
  named "kiosk" (per the older docs) fail to evaluate until kiosk.user is
  set to an unused name, e.g. kiosk.user = "kiosk-display".

### 🐛 Bug Fixes

* **backup:** backed up /etc/nixos by default ([58eb2de](https://github.com/bauer-group/IAC-NixOS/commit/58eb2de0b0993ca445d6b7832a179496909aa6d2))
* **home:** scoped the user environment to the machine's template ([d1fa9b9](https://github.com/bauer-group/IAC-NixOS/commit/d1fa9b9b8747dd72e5f43a2e642ca16eccf0cf15))
* **kiosk:** ran the browser as its own user and repaired the session ([364355f](https://github.com/bauer-group/IAC-NixOS/commit/364355f9ed7c535d62edca1fd8c475e00d088a82))
* **monitoring:** closed the exporter and Grafana to the network ([a3fd11e](https://github.com/bauer-group/IAC-NixOS/commit/a3fd11eac6e312f6bb1b88f1caeba4cd5276b948))
* **users:** required a login credential for the primary account ([2c7cfe6](https://github.com/bauer-group/IAC-NixOS/commit/2c7cfe6c7812b4e28aae855291a44daa6e32c5bd))

## [3.1.0](https://github.com/bauer-group/IAC-NixOS/compare/v3.0.1...v3.1.0) (2026-09-14)

### 🚀 Features

* **monitoring:** disabled Grafana phone-home ([024b83f](https://github.com/bauer-group/IAC-NixOS/commit/024b83f8338078807ca26baac6f261084a9097f8))

## [3.0.1](https://github.com/bauer-group/IAC-NixOS/compare/v3.0.0...v3.0.1) (2026-09-14)

### 🐛 Bug Fixes

* **monitoring:** refused empty Grafana secret keys ([a25c1c4](https://github.com/bauer-group/IAC-NixOS/commit/a25c1c4332bb649e9d84ae02d50147429f84c82c))

### 🔧 Maintenance

* **treefmt:** excluded generated changelog ([f53de8b](https://github.com/bauer-group/IAC-NixOS/commit/f53de8bbf38dea8e9ff5a0b6a7df212a35a62067))

## [3.0.0](https://github.com/bauer-group/IAC-NixOS/compare/v2.0.0...v3.0.0) (2026-09-14)

### ⚠ BREAKING CHANGES

* **nixos:** machines upgrade to NixOS 26.05 with kernel 6.18,
  systemd-based initrd and dbus-broker. LUKS roots must reference
  /dev/mapper/<name>. Machines with allowReboot = false need a manual
  nixos-rebuild boot plus reboot, since the dbus change inhibits switch.
  Monitoring servers must set
  bauergroup.services.monitoring.grafanaSecretKeyFile.

### 🚀 Features

* **nixos:** upgraded to NixOS 26.05 ([4d0f319](https://github.com/bauer-group/IAC-NixOS/commit/4d0f319762811c90324810eab104493dc8995a18))

### 🐛 Bug Fixes

* **auto-update:** appended template to flake URI ([e0b9819](https://github.com/bauer-group/IAC-NixOS/commit/e0b9819e2db5194fa3c6db4b8a991748897df5cc))
* **ci:** added the missing permissions block ([bbc70f2](https://github.com/bauer-group/IAC-NixOS/commit/bbc70f2dcf32e733f025fb38f2321eda3d25c577))
* **ci:** used org PAT for flake update PRs ([f08db7e](https://github.com/bauer-group/IAC-NixOS/commit/f08db7e11a8e852f65c5712a03f3f6e1109f1c99))
* **secrets:** kept secret paths out of Nix store ([923cb9d](https://github.com/bauer-group/IAC-NixOS/commit/923cb9dab6080862b16d15b4060386852e471cbb))

### 💄 UI/UX Improvements

* reformatted with nixfmt from NixOS 26.05 ([6e86df3](https://github.com/bauer-group/IAC-NixOS/commit/6e86df3805e14300fdf6ec543c200abae17e4cb0))

### 🔧 Maintenance

* **ci:** bump actions/checkout from 4 to 7 ([#5](https://github.com/bauer-group/IAC-NixOS/issues/5)) ([bcfde85](https://github.com/bauer-group/IAC-NixOS/commit/bcfde855a2e1c0b12760e87b58e5d6740ff7321f))
* **ci:** bump cachix/install-nix-action from 30 to 31 ([#2](https://github.com/bauer-group/IAC-NixOS/issues/2)) ([17ebffd](https://github.com/bauer-group/IAC-NixOS/commit/17ebffd2dfd6a3ae1d8879ef10c9958d88977473))
* **ci:** bump peter-evans/create-pull-request from 7 to 8 ([#3](https://github.com/bauer-group/IAC-NixOS/issues/3)) ([b60b752](https://github.com/bauer-group/IAC-NixOS/commit/b60b7529639836f082eee11b02f2df5f773a4339))
* **ci:** removed redundant teams notification ([8419462](https://github.com/bauer-group/IAC-NixOS/commit/84194625fef6b9d6459f0ad97bf59c80f842dce2))
* **codeowners:** reassigned ownership to core team [skip ci] ([2226208](https://github.com/bauer-group/IAC-NixOS/commit/22262086d9363222814657dc50ad52cf0d4b58b1))

## [2.0.0](https://github.com/bauer-group/IAC-NixOS/compare/v1.2.0...v2.0.0) (2026-03-23)

### ⚠ BREAKING CHANGES

* **namespace:** Existing nixos configurations using `bauer.params` must be
updated to use `bauergroup.params` and all references updated accordingly.

### ♻️ Refactoring

* **namespace:** renamed module namespace from bauer to bauergroup ([954c5b0](https://github.com/bauer-group/IAC-NixOS/commit/954c5b0b87303840d71770d259884b97931471b4))

## [1.2.0](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.6...v1.2.0) (2026-03-23)

### 🚀 Features

* **auto-update:** added configurable auto-update system ([c8e4be6](https://github.com/bauer-group/IAC-NixOS/commit/c8e4be695e437bc4efe8ab7e9a7355875623dc53))

## [1.1.6](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.5...v1.1.6) (2026-03-23)

### ♻️ Refactoring

* remove unused code and parameters ([ce0d96b](https://github.com/bauer-group/IAC-NixOS/commit/ce0d96bee6c2bbc272315af0771327b22cafa6e7))

## [1.1.5](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.4...v1.1.5) (2026-03-23)

### ♻️ Refactoring

* restructured Nix configs and linting ([e3d68ed](https://github.com/bauer-group/IAC-NixOS/commit/e3d68ed1df36408a38797e1a87a0f77dc9628cc6))

## [1.1.4](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.3...v1.1.4) (2026-03-23)

### ♻️ Refactoring

* **ci:** simplified CI and removed configuration fallbacks ([44d14aa](https://github.com/bauer-group/IAC-NixOS/commit/44d14aadb391ef2a6e51c7ab6d2cebd67c1f6746))

## [1.1.3](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.2...v1.1.3) (2026-03-23)

### 🐛 Bug Fixes

* **networking:** fixed DHCP configuration module precedence ([8aacd64](https://github.com/bauer-group/IAC-NixOS/commit/8aacd64d6027ccd9a1efcc0993efaa6bd88274fe))

## [1.1.2](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.1...v1.1.2) (2026-03-23)

### ♻️ Refactoring

* **embedded-dev:** made feature conditional ([6b7c90f](https://github.com/bauer-group/IAC-NixOS/commit/6b7c90fb94849b8d094961a78c951afabb16fe42))

## [1.1.1](https://github.com/bauer-group/IAC-NixOS/compare/v1.1.0...v1.1.1) (2026-03-23)

### 🐛 Bug Fixes

* **ci:** changed nix fmt check flag to CI mode ([ac9e649](https://github.com/bauer-group/IAC-NixOS/commit/ac9e649e9ad7c27f996d291c0ead9fbc05f9711e))
* **ci:** exclude workflow files from formatting ([aa726e9](https://github.com/bauer-group/IAC-NixOS/commit/aa726e9b25c6a5814619b599bc427aa02ebcf112))

## [1.1.0](https://github.com/bauer-group/IAC-NixOS/compare/v1.0.0...v1.1.0) (2026-03-22)

### 🚀 Features

* **ci:** add template builds with CI fallback support ([d4326ee](https://github.com/bauer-group/IAC-NixOS/commit/d4326ee22eff17048decd58fe9f16cbee6d04a81))

### ♻️ Refactoring

* **infra:** migrated to template-based config ([d542cca](https://github.com/bauer-group/IAC-NixOS/commit/d542cca70b6ba36cc574c7c336b2692b2aed7de0))

## [1.0.0](https://github.com/bauer-group/IAC-NixOS/compare/v0.1.0...v1.0.0) (2026-03-22)

### ⚠ BREAKING CHANGES

* **flake:** Existing deployments must migrate to parameter-based
  system. Per-host hardcoded configs no longer supported.

### ♻️ Refactoring

* **flake:** switched to parametric template-based architecture ([018481b](https://github.com/bauer-group/IAC-NixOS/commit/018481bb7071f6a19fe948f8f670657224edab7d))

## [0.1.0](https://github.com/bauer-group/IAC-NixOS/compare/v0.0.0...v0.1.0) (2026-03-21)

### 🚀 Features

* Initial Commit ([1123c82](https://github.com/bauer-group/IAC-NixOS/commit/1123c8221dd8f310ae6cc408b9d4f491e909f8dd))
