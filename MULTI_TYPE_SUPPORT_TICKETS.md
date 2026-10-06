# Multi-Type Support Tickets

The ticket system now supports a shared company support/operations queue while preserving IT Support access for normal members.

## Who can raise tickets
- All active company members (except Client Viewer in the UI) can raise **IT Support** tickets.
- QA / Tester, Team Lead, Company Admin, IT Admin, DevOps, and Platform Super Admin can additionally raise the broader internal ticket types listed below.

## Ticket types
- IT Support
- QA / Bug Report
- Project / Delivery Blocker
- Access / Permission
- Infrastructure / DevOps
- Production Incident
- Security / Compliance
- Data / Reporting

## Shared queue readers
- Platform Super Admin
- Company Admin
- IT Admin
- DevOps
- Project Manager
- Team Lead
- QA / Tester

The ticket owner can always read their own ticket. Other ordinary employees only see their own tickets.

## Ticket management
Assignment and status changes remain limited to Platform Super Admin, Company Admin, IT Admin, and DevOps. Project Managers, Team Leads, and QA/Testers have shared queue review access but do not receive management rights.

## Firestore
Tickets remain company-scoped at:
`companies/{companyId}/tickets/{ticketId}`

Deploy the updated rules after replacing the project:
`firebase deploy --only firestore:rules`
