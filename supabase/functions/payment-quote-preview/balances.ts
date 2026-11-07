type Balance = {
  exhibitor_id: string;
  currency?: string;
  balance_due_cents?: number;
};

/** Use the same current-exhibitor boundary as checkout, including fee carriers. */
export function currentCartBalances(
  balances: Balance[] | null,
  items: { exhibitor_id: string }[],
): Balance[] {
  const current = new Set(items.map((item) => item.exhibitor_id));
  return (balances ?? []).filter((balance) =>
    current.has(balance.exhibitor_id)
  );
}
