# IT Support Tickets + Web Home Page Update

## Added: IT Support ticket workflow

Firestore path:

`companies/{companyId}/tickets/{ticketId}`

Ticket conversation path:

`companies/{companyId}/tickets/{ticketId}/messages/{messageId}`

### Behavior
- Every active workspace user can raise a ticket.
- The destination is hard-locked to **IT Support** (`assignedTeam: itSupport`).
- Regular users only load their own tickets.
- Queue review access: Super Admin, Company Admin, IT Admin, DevOps, Project Manager, Team Lead, QA / Tester.
- Ticket assignment/status management: Super Admin, Company Admin, IT Admin, DevOps.
- Team Lead, Project Manager and QA / Tester have read-only queue oversight.
- Ticket owner and IT/admin handlers can reply in the ticket conversation.
- IT Admin / DevOps are treated as the IT Support handling team in the existing role model.

### Employee APK / employee web
A persistent **IT Ticket** action is available alongside the existing assistant launcher. It opens the native ticket screen without depending on the server-driven menu JSON. The `tickets` route/action is also registered so a future SDUI design can link to it directly.

### Admin / management web
A new **IT Tickets** navigation section is available in the fixed admin dashboard shell.

## Added: Decorative public web home page

Web no longer opens directly on the login form.

The new landing page includes:
- branded hero section
- responsive dashboard preview
- platform capability cards
- delivery workflow section
- role/access overview
- IT Support workflow section
- sign-in CTAs
- responsive footer

Native APK startup is unchanged and still uses the existing authentication gate directly.

## Firestore security rules
Rules were extended to enforce the ticket role model and IT-only destination on the server side. No composite Firestore index is required by the current queries.

Deploy the updated rules:

```bash
firebase deploy --only firestore:rules
```

Then rebuild/deploy your Flutter web app and APK as usual.

## Cloudinary
The previous Cloudinary file/media upload implementation is untouched by this update. Ticket metadata/messages use Firestore; no Firebase Storage media upload was added.
