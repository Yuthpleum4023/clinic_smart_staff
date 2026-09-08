"use strict";

function s(v) {
  return String(v ?? "").trim();
}

function assertReadOnlyDriver(driver) {
  if (!driver || driver.readOnly !== true) {
    throw new Error("SOURCE_DRIVER_MUST_BE_READ_ONLY");
  }
  for (const name of ["connect", "poll", "close"]) {
    if (typeof driver[name] !== "function") {
      throw new Error(`SOURCE_DRIVER_METHOD_REQUIRED:${name}`);
    }
  }
  return driver;
}

class DriverRegistry {
  constructor() {
    this.factories = new Map();
  }

  register(id, factory) {
    const key = s(id);
    if (!key) throw new Error("DRIVER_ID_REQUIRED");
    if (typeof factory !== "function") throw new Error(`DRIVER_FACTORY_REQUIRED:${key}`);
    if (this.factories.has(key)) throw new Error(`DRIVER_ALREADY_REGISTERED:${key}`);
    this.factories.set(key, factory);
  }

  create(id, config = {}) {
    const key = s(id);
    const factory = this.factories.get(key);
    if (!factory) throw new Error(`DRIVER_NOT_FOUND:${key}`);
    return assertReadOnlyDriver(factory(config));
  }
}

module.exports = { DriverRegistry, assertReadOnlyDriver };
