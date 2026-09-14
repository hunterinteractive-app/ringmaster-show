# One-Time Exhibitor Fee

Show Fees & Payments includes a disabled-by-default One-Time Exhibitor Fee card for the same eligible shows as BBOS and Wave Schedule. Access reuses `can_configure_best_opposite_final_award`; adding a secretary to the existing `best_of_best_opposite` allowlist grants all three options to that secretary’s shows under the existing show permissions.

The secretary enters a custom name and a positive amount with at most two decimal places. The full show assesses one charge per exhibitor number, across sections, species, waves and later carts. Separate exhibitor numbers on a household account each receive their own charge. Enabling the option also assesses every already-entered exhibitor, including paid and manually entered exhibitors. Existing payment records remain unchanged; previously paid exhibitors get a separate amount due.

Charges retain the name and amount assessed. Changing the configuration affects exhibitors not already charged. Turning the option off prevents new assessments and preserves existing balances. An unsubmitted draft can transfer its fee to the cart that checks out first; removing that exhibitor’s last draft item releases the unsubmitted assessment. Pending or completed payments prevent transfers. Reassigning an entry assesses a newly entered exhibitor.

## Billing

- Private ledger `exhibitor_fees_private.charges` uniquely identifies show/exhibitor number and show/exhibitor ID. Transaction advisory locks serialize assessment and concurrent checkout.
- The charge joins the ordinary balance in its first entered section. Existing paid balances are protected; a fee-only cart supports later assessments and manual-entry exhibitors. Its internal carrier never becomes an animal entry or affects animal/fur counts or entry discounts.
- Existing balance, check-in sheet, check-in payment, and scoped financial-report totals include the charge in show fees. Payment line items and the cart show the custom fee name and amount.
- `get_cart_exhibitor_fees` checks household/show access and returns only the caller’s authorized cart charges. Configuration triggers enforce entitlement and show locking. The ledger and carrier controls cannot be edited by exhibitors.
- Ordinary shows keep the feature off and retain the existing calculation behavior.

## Release and verification

Database migration `20260914091005_add_one_time_exhibitor_fee.sql` is deployed to `yzjoycrvqkyfrksmaixf`. No show was enabled and no live fee was assessed during deployment. The local Flutter web app at `http://127.0.0.1:8080/` was hot-reloaded for testing.

Validation: 31 transactional fee assertions; online quote, custom receipt, finalization/replay and fee-only payment integration; existing payment-hardening contracts; four Chrome widget tests for selected/unselected secretaries, household cart totals, and mobile fee-only carts; clean targeted Flutter analysis. Two simultaneous local checkout transactions for the same exhibitor produced one charge and one fee across both quotes. All local financial test fixtures were rolled back or cleaned up.

Post-deployment checks confirmed zero enabled shows and zero assessed charges. Security advisors reported no new findings. The local browser was checked visually: the restricted card and custom fields load correctly, and the switch was left off without saving a fee.
