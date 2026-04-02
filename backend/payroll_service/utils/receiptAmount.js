function round2(v) {
  const n = Number(v || 0);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100) / 100;
}

function toNonNegativeNumber(v) {
  const n = Number(v || 0);
  if (!Number.isFinite(n)) return 0;
  return n < 0 ? 0 : n;
}

function normalizeReceiptItem(item = {}) {
  const quantity = toNonNegativeNumber(item.quantity || 1);
  const unitPrice = toNonNegativeNumber(item.unitPrice || 0);

  let amount = Number(item.amount);
  if (!Number.isFinite(amount)) {
    amount = quantity * unitPrice;
  }

  return {
    description: String(item.description || "").trim(),
    quantity: round2(quantity),
    unitPrice: round2(unitPrice),
    amount: round2(toNonNegativeNumber(amount)),
    note: String(item.note || "").trim(),
  };
}

function sumItems(items = []) {
  return round2(
    (Array.isArray(items) ? items : []).reduce((sum, item) => {
      return sum + toNonNegativeNumber(item.amount);
    }, 0)
  );
}

function calculateReceiptAmounts({
  items = [],
  subtotal,
  withholdingTax,
  withholdingPercent,
} = {}) {
  const normalizedItems = (Array.isArray(items) ? items : [])
    .map(normalizeReceiptItem)
    .filter((item) => item.description);

  const derivedSubtotal =
    Number.isFinite(Number(subtotal)) && Number(subtotal) >= 0
      ? round2(Number(subtotal))
      : sumItems(normalizedItems);

  let derivedWithholdingTax = 0;

  if (Number.isFinite(Number(withholdingTax)) && Number(withholdingTax) >= 0) {
    derivedWithholdingTax = round2(Number(withholdingTax));
  } else if (
    Number.isFinite(Number(withholdingPercent)) &&
    Number(withholdingPercent) >= 0
  ) {
    derivedWithholdingTax = round2(
      derivedSubtotal * (Number(withholdingPercent) / 100)
    );
  }

  const netAmount = round2(
    Math.max(0, derivedSubtotal - derivedWithholdingTax)
  );

  return {
    items: normalizedItems,
    subtotal: derivedSubtotal,
    withholdingTax: derivedWithholdingTax,
    netAmount,
  };
}

module.exports = {
  round2,
  toNonNegativeNumber,
  normalizeReceiptItem,
  calculateReceiptAmounts,
};