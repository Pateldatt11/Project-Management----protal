# v228 - PageView Stack Carousel

- Reworked the phase carousel to use a PageView-driven circular queue.
- The carousel now behaves like the StackOverflow PageView pattern: drag/scroll is controlled by PageView while cards scale, overlap, and depth-shift around the active page.
- Kept circular infinite swipe behavior.
- Kept one-tap global phase detail unlock behavior.
- Side-card tap still focuses the tapped phase through the PageView page target.
- Existing task timeline, auth, and calendar fixes from v227 are preserved.
