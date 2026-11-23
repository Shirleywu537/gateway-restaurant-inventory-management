# Invoice PDF receiving

Implemented November 16, 2026 for the existing restaurant owner portal and Supabase project.

## Use the feature

1. Sign in as a restaurant owner or manager and select the restaurant.
2. Make sure the ingredients, supplier, and purchase order already exist. Orders must be Ordered or Partially received.
3. Open **Receiving → Upload invoice PDF**. Select an English PDF, up to 20 MB and 10 pages.
4. Review the PDF preview, invoice number, supplier, selected purchase order, and received quantities. Quantities are in each ingredient's base unit. Enter zero for goods not delivered.
5. Confirm that the goods arrived and have not already been recorded manually, then choose **Confirm receipt & update stock**.
6. Check Receiving history, Purchase orders, Ingredients, and Transactions. The receipt notes include the invoice number and filename.

Text PDFs use their text layer. Image-only pages use English OCR. Use the all-pages OCR checkbox for mixed documents or an inaccurate text layer. Password-protected PDFs must be unlocked before use.

The public sample workspace accepts the two downloadable fictional PDFs and previews stock/order changes. It never writes sample records to the database.

## Matching and review rules

- Explicit purchase-order numbers and supplier names are matched to existing records only when unique. The user can select another open order.
- Ingredient names, internal SKUs, and supplier SKUs are matched to text rows. A suggested quantity requires a single matching row and one explicit quantity/unit pair.
- Prices and invoice totals are not treated as quantities. Ambiguous pack expressions and multiple matching lines require manual entry.
- Matching units, grams/kilograms, and milliliters/liters can be converted. An exact catalog pack-unit match uses its existing base-units-per-pack value. Other conversions require review and manual input.
- A scan is a suggestion, not evidence that a delivery occurred. Every receipt requires the user's explicit check of actual delivered quantities. Credit notes and returns cannot be posted through this flow.

## Database effects and safeguards

`receive_invoice` performs all writes in one transaction and delegates quantity/stock handling to the existing `receive_purchase_order` function. It creates a goods receipt and receipt lines, adds receipt stock movements, and sets the order to Partially received or Received according to its remaining quantities. An error rolls back the entire operation.

`invoice_imports` links invoice provenance to the restaurant, supplier, purchase order, and receipt. Only that restaurant's owners/managers can read this table; app users cannot write it directly. The function checks owner/manager membership, restaurant/supplier/order consistency, quantity limits, and required metadata. Existing supplier access is unchanged. Connected suppliers see the ordinary permitted order/receipt projection, without internal stock, invoice metadata, receipt notes, usage, or waste.

A SHA-256 file fingerprint blocks the same PDF from being posted twice within a restaurant. A normalized invoice number blocks repeat invoice receipts for the same restaurant and supplier. A stable request ID makes an identical retry safe; reusing it with changed details fails. Restaurant-level locking and database unique constraints protect duplicate checks during simultaneous requests.

## Privacy and limits

- The original PDF, preview images, and raw extracted text stay in browser memory; they are not uploaded to Supabase or an external OCR service. Keep the original invoice separately. Confirmed receipt metadata, invoice number, filename, file size, fingerprint, extraction method, and reviewed quantities are saved.
- One invoice can be posted once against one purchase order. Multi-order invoices and later deliveries under the same invoice need manual Receiving or separate delivery invoices. No invoice editing or reversal workflow is provided.
- Duplicate protection covers this invoice workflow. It cannot infer whether the same goods were already entered through manual Receiving or a stock adjustment; the user must check before confirmation.
- This is receiving and stock management, not accounts payable: taxes, prices, totals, payment status, and supplier balances are not imported.
- OCR supports English printed text. Handwriting, blurred scans, complex tables, unusual units, and ambiguous item names can need manual correction. Document limits are 20 MB and 10 pages. Older browsers may not support the required PDF/WASM features.
- The PDF is not stored as a cloud attachment. No original-document download is available from receipt history.

## Validation

The invoice migration was first tested inside a rolled-back transaction, then committed to the existing project. The standalone database suite passed all 19 checks after application, with every temporary record rolled back. Checks cover partial and complete receiving, stock changes, receipt linkage, exact retries, duplicates, incorrect supplier/restaurant, over-receipts, multi-line failure rollback, metadata limits, staff/outsider/anonymous denial, and supplier receipt visibility without invoice data.

Local Chrome tests successfully scanned both a text PDF and an image-only PDF. Both identified DEMO-INV-2026-001, Metro Produce, DEMO-PO-001, and 3 kg of tomatoes. The sample preview showed stock changing from 17 kg to 20 kg with the order remaining partially received, without saving. Automated JavaScript checks and publication results are recorded in VALIDATION.md and the deployment report.
