"use strict";

function s(v) {
  return String(v ?? "").trim();
}

class AdapterRegistry {
  constructor() {
    this.adapters = new Map();
  }

  register(adapter) {
    const id = s(adapter?.id);
    if (!id) throw new Error("ADAPTER_ID_REQUIRED");
    if (this.adapters.has(id)) throw new Error(`ADAPTER_ALREADY_REGISTERED:${id}`);
    if (typeof adapter.transformRecord !== "function") {
      throw new Error(`ADAPTER_TRANSFORM_REQUIRED:${id}`);
    }
    this.adapters.set(id, Object.freeze({ ...adapter, id }));
    return this.adapters.get(id);
  }

  get(id) {
    const key = s(id);
    const value = this.adapters.get(key);
    if (!value) throw new Error(`ADAPTER_NOT_FOUND:${key}`);
    return value;
  }

  list() {
    return [...this.adapters.keys()].sort();
  }
}

module.exports = { AdapterRegistry };
