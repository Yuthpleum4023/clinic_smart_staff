"use strict";

const fs = require("fs");
const path = require("path");

const {
  assembleProductionConfig,
} = require("./productionConfigAssembler");

function loadRuntimeConfig(filePath, env = process.env, deps = {}) {
  const config = JSON.parse(fs.readFileSync(path.resolve(filePath), "utf8"));

  return assembleProductionConfig(config, {
    env,
    profileRegistry: deps.profileRegistry,
  });
}

module.exports = { loadRuntimeConfig };
