# Cloudinary File Upload Fix

## Storage architecture
- Actual attachment bytes/media are uploaded to **Cloudinary**.
- Firebase Storage is **not** used by the task attachment flow.
- Firestore stores only attachment metadata needed by the existing workspace/task system: Cloudinary `secureUrl`, `publicId`, filename, MIME type, file size, task/project IDs and uploader ID.

## Fixes applied
1. Cloudinary upload endpoint changed from `image/upload` to `auto/upload` so PDFs, Word, Excel, TXT and images can use the same upload flow.
2. Upload UI now receives real byte progress from the Cloudinary request instead of a fake timer / fixed 4.2 MB animation.
3. Removed the fake `task_document.pdf` and `https://example.com` local attachment.
4. Upload success is shown only after Cloudinary returns a real URL and attachment metadata has been saved.
5. Attachment metadata save retries up to 3 times before reporting failure.
6. Attachment metadata stream is loaded for all task-visible roles, not only manager/HR roles.
7. Files tab merges the attachment stream with task-embedded attachments and de-duplicates by attachment ID.
8. Employee APK task cards also show live Cloudinary upload progress and real uploaded/total bytes.
9. Firestore rules include collection-group access for attachment metadata and allow assigned users to mirror attachment metadata/counts into their task document.

## Deploy after updating the project
Only Firestore rules changed for this fix. Do not deploy Firebase Storage rules for this attachment change.

```bash
firebase deploy --only firestore:rules
```

## Cloudinary configuration
The existing values in `lib/core/config/cloudinary_config.dart` are preserved. Ensure the configured upload preset is an **unsigned upload preset** if uploads are performed directly from APK/web clients.
