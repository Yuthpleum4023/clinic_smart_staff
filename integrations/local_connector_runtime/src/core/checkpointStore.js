"use strict";

const fs = require("fs");
const path = require("path");

class FileCheckpointStore {
  constructor(filePath) {
    this.filePath = path.resolve(filePath);
  }

  load() {
    if (!fs.existsSync(this.filePath)) return {};
    const text = fs.readFileSync(this.filePath, "utf8").trim();
    return text ? JSON.parse(text) : {};
  }

  get(key) {
    return this.load()[String(key)] ?? null;
  }

  set(key, value) {
    const state = this.load();
    state[String(key)] = value;
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });

    const tmp = `${this.filePath}.tmp-${process.pid}`;
    fs.writeFileSync(tmp, JSON.stringify(state, null, 2), "utf8");
    fs.renameSync(tmp, this.filePath);
  }
}

module.exports = { FileCheckpointStore };
