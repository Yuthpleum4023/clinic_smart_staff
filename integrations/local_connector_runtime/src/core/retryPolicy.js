"use strict";

function positiveInt(value, fallback, max) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return fallback;
  return Math.min(n, max);
}

function createRetryPolicy(config = {}) {
  const initialDelayMs =
    positiveInt(config.initialDelayMs, 5000, 3600000);

  const maxDelayMs =
    Math.max(
      initialDelayMs,
      positiveInt(config.maxDelayMs, 300000, 3600000)
    );

  const multiplierRaw = Number(config.multiplier);
  const multiplier =
    Number.isFinite(multiplierRaw) && multiplierRaw >= 1
      ? Math.min(multiplierRaw, 10)
      : 2;

  function delayForFailureCount(failureCount) {
    const count = Math.max(1, Number(failureCount) || 1);
    const exponent = Math.max(0, count - 1);

    return Math.min(
      maxDelayMs,
      Math.round(initialDelayMs * Math.pow(multiplier, exponent))
    );
  }

  return Object.freeze({
    initialDelayMs,
    maxDelayMs,
    multiplier,
    delayForFailureCount
  });
}

module.exports = { createRetryPolicy };
