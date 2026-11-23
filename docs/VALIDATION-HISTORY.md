# Frontend validation — November 2, 2026

## Environment and scope

The browser preview at `http://127.0.0.1:4173` was connected to the existing hosted Supabase project `dokvovzhcyeypooktfum`. The project owner personally created an application account, confirmed the email, and signed in. No password or user session token was extracted or put into source files.

Live writes were made only through the website in **Gateway QA — Website validation**, a separate restaurant created for these checks. Its fictional records are deliberately retained for review. The owner's **the owner’s separate restaurant** restaurant was not populated with test data. The earlier database demonstration restaurant remains separate.

## Observed browser results

| Check | Observed result |
| --- | --- |
| Sign-in and onboarding | Confirmed user account loaded its memberships; restaurant creation added a separate QA workspace. |
| Add ingredient | QA Tomatoes / QA-TOMATO saved with kg as base unit and a 10 kg reorder point. |
| Opening inventory | A +10 kg opening transaction saved and the balance became 10 kg. |
| Add supplier | QA Produce Supplier saved, with a fictional `example.invalid` email and a two-day lead time. |
| Supplier catalog | A 5 kg case at $12.50 saved; selecting it in an order suggested $2.50 per kg. |
| Create order | QA-WEB-001 saved for 20 kg at $2.50 per kg, total $50.00. |
| Partial receipt | Receiving 12 kg changed the order to Partially received and inventory to 22 kg. |
| Usage | Recording 4 kg usage reduced inventory to 18 kg. |
| Insufficient stock | Attempted 99 kg usage was blocked by the frontend with an inline below-zero warning; no fourth ledger entry was created. |
| Edit ingredient | Changing the reorder point from 10 kg to 20 kg saved and changed the 18 kg balance flag to Low stock; SKU and unit remained fixed. |
| Transaction history | The three entries were +10 opening, +12 receipt, and −4 usage. |
| Transaction filters | Choosing Receipt returned the single +12 kg entry. |
| Workspace switch | Switching to the owner’s separate restaurant cleared the QA data and showed zero transactions. |
| Persistence | A full browser reload restored the signed-in session and the same three database transactions. |

## Automated and API checks

- `npm run check`: JavaScript syntax checks passed.
- `npm test`: 9 tests passed, covering line validation, partial receipts, quantity signs and roles, retry IDs and payloads, escaping, restaurant-scoped reads/writes, and server-side transaction pagination/filtering.
- The hosted Auth settings endpoint returned HTTP 200 and confirmed email login, signup, and email confirmation were enabled.
- An unauthenticated request to protected inventory data returned HTTP 401 / PostgreSQL 42501, rather than restaurant data.
- Database authorization/workflow integration checks were previously run on October 29 (17 passed); they were not rerun or represented as new browser checks.

## Limits of this verification

Browser writes were checked with the owner's application role. No new staff/viewer accounts were created, no concurrent load test was performed, and password-reset email delivery was not exercised. The insufficient-stock browser check validates frontend behavior; the database constraint was covered by the earlier database integration tests. Publication and hosted-origin smoke checks are recorded separately after deployment.

# Portal update validation — November 9, 2026

- Website syntax checks passed; 13 automated tests passed (including unit separation, currency separation, empty/escaped charts, supplier navigation, and exclusion of private fields from rendered supplier pages).
- Five offline-demo tests passed, including login selection and both portal render paths.
- The supplier migration passed 15 checks inside a rollback-only transaction before application. After user approval it was committed to the existing Supabase project; the standalone 15-check suite passed again with all temporary users and fixtures rolled back. No existing supplier was connected and no restaurant data was changed by the migration.
- Browser checks confirmed real-app owner/supplier login selection, both read-only sample portals, role-specific navigation, and the new charts.
- Offline browser workflow: Tomatoes started at 17 kg; receiving 3 kg and recording 2 kg usage left 18 kg. After switching roles the supplier order showed 20 kg ordered, 15 kg received, and 5 kg outstanding, without current stock or usage. A pending fictional restaurant connection was accepted successfully. Stock-chart unit selection changed the displayed ingredient set.

Browser review of the portable HTML used an isolated localhost server. Direct double-click file opening was not tested by automation. New live supplier onboarding/connection actions have database integration coverage but have not been exercised through an authenticated browser account. No concurrent load test, supplier-team invitation test, or hosted email callback test was performed. Hosted smoke-test results are recorded separately with publication results.

## Hosted smoke check

Publication succeeded at the existing inventory Site on November 9. Its owner-private audience was preserved. The hosted login opened successfully and selected the supplier layout; the read-only supplier sample loaded charts and restaurant connections. Selecting The Olive Table filtered orders to that restaurant. The role switch and owner stock charts were also checked. Samples are fictional; these checks do not represent authenticated live supplier onboarding. Final publication identifiers are retained in the separate deployment report.

# Invoice receiving validation — November 16, 2026

- Syntax checks passed and all 18 JavaScript tests passed. Five invoice-focused tests cover matching, quantity extraction, ambiguous packs, units, confirmation, over-receipts, duplicate line mappings, identifiers, and PDF metadata limits.
- The migration and its 19-check suite first passed together in a rollback-only dry run. The invoice migration was then committed to the existing Supabase project. All 19 standalone integration checks passed again and their temporary data was rolled back. Existing restaurant records were not altered by these checks.
- Local Chrome successfully uploaded the fictional text PDF and image-only scanned PDF. Both matched invoice DEMO-INV-2026-001, Metro Produce, order DEMO-PO-001, and 3 kg tomatoes. Image-only input visibly used OCR and produced no application console errors.
- The read-only preview correctly showed 17 kg + 3 kg = 20 kg and Partially received, with one Receiving line proposed and no mutation.
- Owner/manager-only invoice access, duplicate PDF/invoice-number rejection, identical retry safety, over-receipts, wrong supplier/restaurant, partial and complete statuses, stock/receipt linkage, multi-line rollback, and supplier receipt projection were checked in the database suite.
- These checks distinguish database integration, local UI behavior, and real account browser writes. Final hosted smoke checks and any authenticated browser checks are recorded separately in the dated deployment report. No real customer invoices were used.

The site was verified public at the start of this update; the current audience is preserved. Earlier owner-private notes above describe the November 9 publication, not the current sharing state.

# Multiple supplier workspaces — November 16, 2026

- Supplier Account navigation is now labeled Workspace, preserving the existing workspace route and connection code.
- A signed-in supplier member can create another business using the existing retry-safe database function. Creation selects the returned membership; switching clears account-specific data and filters. The selected membership is remembered per signed-in user on this browser, and stale/non-member saved IDs are discarded.
- Syntax checks and 20 JavaScript tests passed, including membership selection, business-name validation, and sample write restrictions.
- Local browser review confirmed the new Workspace layout, independent-business explanation, connection code, and disabled sample create button.
- No database migration or access-policy change was required. Hosted creation/switching verification is recorded separately with the deployment report.

# Connection code in Add supplier — November 16, 2026

- New supplier forms show an optional connection code and explain supplier approval and shared order/receipt data.
- Entering a code changes the submit button to Add & request connection. Blank codes preserve contact-only creation.
- Malformed codes and inactive suppliers are rejected before writing. A confirmed supplier save is retained if requesting the connection fails; correcting the code and retrying updates the same supplier ID.
- The form prevents overlapping submissions and closing while saving. Existing Manage connection remains available for later management.
- Syntax checks and all 25 automated tests passed. Local preview returned HTTP 200 and loaded the sign-in page. Authenticated end-to-end verification uses the hosted QA workspace and is recorded separately after deployment.
- No database migration or access-policy changes; supplier acceptance remains required.
