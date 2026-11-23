# Gateway Restaurant Inventory Management

A restaurant supply-chain website with separate restaurant-owner and supplier portals, backed by Supabase Auth and PostgreSQL.

**[Open the live website](https://gateway-restaurant-inventory.ww537136522.chatgpt.site/)** → choose **Restaurant owner** or **Supplier**, then open the **sample workspace** to review the interface without creating an account. Samples are fictional and do not save changes to the database.

## What the website does

| Restaurant owners | Suppliers |
| --- | --- |
| Create and switch restaurant workspaces | Create and switch supplier businesses |
| Manage ingredients, reorder points, supplier contacts and catalog quotes | Share a connection code and accept or decline restaurant connection requests |
| Create purchase orders and receive partial or complete deliveries | Review connected restaurants and their own orders and deliveries |
| Scan invoice PDFs, review suggested quantities, then update stock, order progress and Receiving together | View order-status and order-value charts |
| Record opening stock, usage, waste and adjustments; view stock charts | Keep restaurant internal stock, usage, waste and other suppliers private |

The latest updates include invoice PDF scanning, creating additional supplier workspaces, and entering a connection code directly in **Suppliers → Add supplier**. Supplier acceptance is required before connected data becomes available.

## Run locally

Use Node.js 24 (the version used for the export checks) and npm:

```sh
git clone https://github.com/Shirleywu537/gateway-restaurant-inventory-management.git
cd gateway-restaurant-inventory-management
npm ci
npm run vendor:ocr
npm run dev
```

Open **http://127.0.0.1:4173**. Keep the server running. Do not open `dist/index.html` directly as a local file: browser modules and OCR workers need an HTTP server.

The application source is in `dist/`; no bundler or application build is needed. `vendor:ocr` copies the pinned PDF.js, Tesseract, English OCR data and their license notices into `dist/vendor/invoice/`. These generated assets are intentionally excluded from Git. Run that command before trying invoice scanning or deploying a copy. The Supabase browser library and its license are included in `dist/vendor/`.

The checked-in `dist/config.js` points to the existing application backend using its **browser-public publishable key**. The sample workspace uses fictional local data. Signed-in operations use the existing database and its membership permissions; use a designated test restaurant for testing. No database password, service-role key, session token, or database export is included.

## For reviewers

1. Explore both sample portals and compare their navigation and charts.
2. In the owner sample, open Receiving and try the supplied [text invoice](dist/examples/sample-invoice.pdf) or [scanned invoice](dist/examples/sample-invoice-scan.pdf). Review the proposed changes; the sample does not save them.
3. Read [Portal workflows and permissions](PORTALS.md) and [Invoice matching, privacy and limits](INVOICE-RECEIVING.md).
4. Read the [database guide](docs/DATABASE.md) for table relationships, migration order and an independent backend setup.
5. Run the checks below. [Validation history](docs/VALIDATION-HISTORY.md) distinguishes prior browser and database checks from this source export.

```sh
npm run check
npm test
```

## Repository map

```text
dist/                  Website HTML, CSS and JavaScript; fictional demo data
dist/examples/         Two fictional invoice PDFs for OCR review
dist/vendor/           Supabase library; generated OCR assets after setup
scripts/               Local server, OCR asset setup and PDF fixture generator
tests/                 JavaScript workflow, input and rendering tests
supabase/migrations/   Ordered database schema and workflow migrations
supabase/tests/        Rollback-based SQL authorization and workflow tests
supabase/seed_demo.sql Optional fictional database teaching dataset
docs/                  Database setup, review notes and validation history
```

## Architecture and current limits

The browser uses Supabase Auth, restaurant-scoped reads, and authorized database functions for business transactions. Database row-level security and membership checks enforce access; choosing a portal does not grant access. Receiving writes the receipt, receipt lines, stock movements and order status in one database transaction.

PDF text extraction and English OCR run in the browser. The original PDF is not saved to cloud storage. Users must check the actual delivery and confirm the proposed receipt; OCR is not an automatic inventory update.

This is an MVP: one stock pool per restaurant, no POS integration, recipes, expiry batches, stock transfers, payments or accounts payable. There is no automatic live synchronization; use Refresh for other users' changes. Staff invitations and role management are not exposed in the website. Concurrent load testing and a broader production-readiness review remain outstanding.

## Hosting and sharing

This repository is a source handoff, separate from the existing hosted website. Pushing changes here does **not** automatically deploy the live site. To host an independent copy, generate the OCR assets, serve `dist/` over HTTPS, and configure its backend and Auth callback URLs as described in the database guide.

The repository is private. A reviewer needs a GitHub account and an accepted repository invitation to view or clone it. The live website's sample workspace is publicly accessible independently of repository access.

Snapshot prepared November 23, 2026 from website source commit `92fb7a98c50336cec2e518666850e7c13571c6a3`. Application modules are preserved; this handoff adds documentation and excludes generated OCR assets, local caches, hosting internals and QA evidence files. Original project code has no open-source license granted here; third-party components retain their included licenses.
