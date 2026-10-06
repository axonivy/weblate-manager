# Weblate Manager

[![CI Build](https://github.com/axonivy/weblate-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/axonivy/weblate-manager/actions/workflows/ci.yml)

Dev-ops tooling for our Weblate translated components.

## Translation components

- 📊️ **Auditing**: reports translation components. See [workflows/weblate-audit.yml](https://github.com/axonivy/weblate-manager/actions/workflows/weblate-audit.yml) > Click on the latest run to see Markdown report.
- 🚢️ **Onboarding**: adds new translation components with minimal time and our preferred [defaults](./defaults.json). See the [onboarding guide](./doc/ONBOARD.md). 
- ⚙️ **Configuring**: change settings of one or many translation components via CLI. See [update-components.sh](./scripts/update-components.sh)

