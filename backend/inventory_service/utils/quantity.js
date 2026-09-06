const SCALE = 1000;

function finiteNumber(v, label = "quantity") {
  const n = Number(v);
  if (!Number.isFinite(n)) {
    const err = new Error(`${label} must be a finite number`);
    err.status = 400;
    err.code = "INVALID_QUANTITY";
    throw err;
  }
  return n;
}

function qty(v, label = "quantity") {
  return Math.round(finiteNumber(v, label) * SCALE) / SCALE;
}

function positiveQty(v, label = "quantity") {
  const n = qty(v, label);
  if (n <= 0) {
    const err = new Error(`${label} must be greater than zero`);
    err.status = 400;
    err.code = "INVALID_QUANTITY";
    throw err;
  }
  return n;
}

module.exports = { qty, positiveQty };
