# Company In-App Campaigns

This build adds company-scoped in-app campaigns without changing the platform-global APK/SDUI architecture.

## Company Admin flow

Open the normal company web portal and select **Campaigns** in the navigation.

Company Admin or Platform Super Admin can:
- create campaign drafts;
- use quick templates for promotions, announcements, onboarding and maintenance;
- choose modal, top banner or bottom-card presentation;
- target all company users or selected employee roles;
- show once per user or once per app session;
- set a CTA label and optional HTTPS URL;
- choose a run duration;
- Run Campaign, Pause, End, Edit or Delete.

## Firestore paths

Campaign content is company-specific:

`companies/{companyId}/inAppCampaigns/{campaignId}`

Per-user acknowledgement is stored at:

`companies/{companyId}/members/{uid}/campaignReceipts/{campaignId}`

The mobile UI/SDUI design remains platform-global under `platformUiConfigs/*` and is not duplicated per company.

## Employee app behavior

The employee app listens only to `running` campaigns in the signed-in user's current company. It filters by start/end time and audience role before showing a campaign. One-time campaigns are suppressed after the user's receipt is saved. Session campaigns show at most once during the current app session.

## Security

Firestore rules allow active company members to read their company's campaigns. Only Company Admin and Platform Super Admin can create/update/delete campaigns. A user can write only their own campaign receipt.

## Deploy

After replacing the project, deploy the updated rules:

`firebase deploy --only firestore:rules`

Then rebuild/deploy the web portal and employee APK/web employee surface.
