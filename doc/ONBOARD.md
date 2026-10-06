# Onboard a Weblate Component

How to add translatable components to [Hosted Weblate](https://hosted.weblate.org/projects/axonivy/#components).


## 1. Manual Github Setup

Github access setup for weblate is not automated, and needs to beconfigured as before weblate onboarding as follows.

### Invite Collaborator

1. Ensure the GitHub repository is public, as required by the free Libre hosting plan described in the source guide.
2. Add the **Weblate (bot)** account as a repository collaborator with `write` access. It takes ~5mins until weblate accepts it.

![collaborator:Weblate (bot)](img/01-github-collaborator.png)

### Setup Webhook

1. Create a new webook for the URI `https://hosted.weblate.org/hooks/github/`

Stick to defaults:
- Payload URL: `https://hosted.weblate.org/hooks/github/`
- Content type: `application/x-www-form-urlencoded`
- Events: push only
- SSL verification: enabled
- Active: enabled

After creating the webhook, check its recent deliveries and confirm Weblate receives a successful push notification.
![GitHub webhook list](img/02-github-webhook-list.png)
![GitHub webhook configuration](img/03-github-webhook-settings.png)


## 2. Automated Weblate onboarding

After Github setup, the onboarding to Weblate can be completed by running the [onboard-component.sh](../scripts/onboard-component.sh) script.

In order to run it, you need an API key from Weblate.
You can lease one in your users settings on Weblate.
Add it to your env variables before running the script.

`WEBLATE_TOKEN=abc_1234xyz ./script/onboard-component.sh`

## 3. Manual Github Finalization

Add a batch to your README.md, so that users can easily access translations.

⚠️ The batch is mandatory, as part of the free hosting agreement.

```md
<!-- replace YOUR_COMPONENT with the component name you onboarded -->
[![translation-status](https://hosted.weblate.org/widget/axonivy/YOUR_COMPONENT/svg-badge.svg)](https://hosted.weblate.org/engage/axonivy/)

```
