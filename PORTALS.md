# Owner and supplier portals — November 9, 2026

The website has two workspaces using the same Supabase Auth login. Choosing a portal is navigation, not a permission grant. A user sees only restaurant memberships or supplier-account memberships granted to that account.

## Connect a restaurant to a supplier

1. The supplier chooses Supplier at login, signs in, and creates a supplier business. Workspace shows its connection code. This identifier is not a password.
2. A restaurant owner or manager opens **Suppliers → Add supplier**, enters the supplier details and optional **Connection code**, then chooses **Add & request connection**. Leave the code blank to save only the supplier details. Confirm that the code belongs to the intended business. For an existing supplier record, use **View supplier → Manage connection**.
3. The supplier sees a pending request in Restaurants and can accept or decline it.
4. After acceptance, the supplier sees that restaurant's existing and future orders placed with its connected supplier record, including prices, ordered quantities, received quantities, and delivery confirmations.
5. An owner or manager can disconnect from Manage connection. Subsequent supplier reads no longer return that restaurant's orders or receipts. Previously viewed or exported information cannot be recalled.

Adding a supplier and requesting a connection are two consecutive saves. A malformed code is rejected before saving. If the supplier saves but the request fails, the form stays open with an explicit message; correcting the code and retrying updates the same supplier ID. The original supplier record remains saved and can be managed later.

No existing supplier is automatically connected. A pending request discloses only the restaurant name, currency, and request status. Supplier account membership does not create restaurant membership.

## Create and switch supplier businesses

From the Supplier portal, open **Workspace → Create another supplier**, enter a business name, and choose **Create supplier**. The new supplier becomes the selected workspace and has its own connection code. The top-right supplier selector switches between memberships and remembers the selection on this browser for the signed-in user. Switching clears prior restaurant filters and data before loading the selected business.

The first supplier is created through the existing setup form. Additional suppliers reuse the same retry-safe `create_supplier_account` function; no database or permission changes are needed. A new supplier has no restaurant connections, orders, or receipts. Existing restaurant records and supplier businesses are unchanged. Samples show a disabled create button and require sign-in for real creation.

## What each portal shows

| Area | Restaurant owner | Supplier |
| --- | --- | --- |
| Navigation | Home, Ingredients, Suppliers, Purchase orders, Receiving, Transactions, Workspace | Overview, Restaurants, Orders, Deliveries, Workspace |
| Inventory | Current stock, reorder points, opening/usage/waste/adjustments | No access |
| Relationships | Own supplier contacts and catalog | Connected or requesting restaurant names |
| Orders | Own restaurant orders; authorized creation/cancellation | Read-only orders placed with that supplier on accepted connections |
| Deliveries | Record partial or complete receipts | Read confirmed receipt quantities |
| Other businesses | Only own restaurant memberships | No other suppliers, private restaurant notes, inventory ledger, or unrelated ingredients |

A product name on a supplier's order identifies what was ordered; it is not an Ingredients page or a current-stock disclosure. The supplier cannot confirm its own receipt or edit restaurant stock.

## Visualizations

- **Stock at a glance:** up to ten active ingredients with the lowest absolute on-hand balances in the selected unit. Reorder-point bars provide a reference. Different units are never added or compared on the same chart; quantities are not automatically converted.
- **Stock health:** counts active ingredients below their reorder point versus those in range. Each ingredient counts once. This is not a value or weight distribution.
- **Order progress:** number of the supplier's visible orders in each current status. Percentages are rounded; labels retain exact counts.
- **Orders by restaurant:** recorded order value for up to eight restaurants, sorted largest first, excluding cancelled orders and restricted to the selected currency. This is order value, not revenue, profit, payment, or current stock.

Charts use the loaded workspace data, update after successful writes/refreshes, and show empty states. No automatic polling or Realtime feed is enabled.

## Database additions and controls

Three tables were added: `supplier_accounts`, `supplier_account_members`, and `restaurant_supplier_connections`. Five API functions create an account, list memberships, request a connection, respond to a connection, and return a limited supplier snapshot. Original restaurant tables and membership policies remain intact. The current schema therefore has thirteen business tables.

The supplier snapshot validates account membership on the server and returns an explicit projection, not unrestricted restaurant rows. Pending, declined, and revoked connections do not provide order access. Browser pages never use a service-role key. Direct supplier reads of restaurant inventory and direct stock writes are denied.

The migration was applied to `dokvovzhcyeypooktfum` on November 9, 2026 after approval. Fifteen isolation/workflow checks passed both before application (full rollback) and after application (test fixtures rolled back). They cover account retries, outsider denial, pending/accepted/revoked access, own-order scoping, private-field exclusion, direct-read/write denial, connection approval rules, and anonymous denial.

## Current limits

This is an MVP. Supplier account creation is available, but staff invitations, supplier team management, account editing, self-service business verification, dispatch notices, invoices, payments, returns, and supplier-owned warehouse stock are not implemented. Restaurant membership remains separately administered. Supplier snapshots load all permitted order history in one response; pagination and date filters are needed before large production use. Order quantities and amounts are recorded facts, not forecasts or accounting reports.

The offline demo uses fictional, tab-local data. Its role selection and connections simulate the live workflow; they are not authentication. Reload or Reset demo restores its examples. It does not connect to Supabase or send actual orders.
