"use strict";

const fs = require("fs");
const path = require("path");

class FileHealthStore {
  constructor(filePath) {
    this.filePath = path.resolve(filePath);
  }

  write(snapshot) {
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });

    const tmp = `${this.filePath}.tmp-${process.pid}`;

    fs.writeFileSync(
      tmp,
      JSON.stringify(snapshot, null, 2) + "\n",
      "utf8"
    );

    fs.renameSync(tmp, this.filePath);
  }

  read() {
    if (!fs.existsSync(this.filePath)) return null;

    const text = fs.readFileSync(this.filePath, "utf8").trim();
    return text ? JSON.parse(text) : null;
  }
}

module.exports = { FileHealthStore };
