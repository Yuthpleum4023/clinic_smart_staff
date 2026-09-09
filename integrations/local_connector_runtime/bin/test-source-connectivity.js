#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const {
  checkMySqlSourceConnectivity
} = require(
  "../src/connectivity/mysqlSourceConnectivity"
);

function s(value) {
  return String(value ?? "").trim();
}

async function main() {
  const configPath =
    path.resolve(
      s(process.argv[2])
    );

  if (!s(process.argv[2])) {
    throw new Error(
      "CONNECTIVITY_CONFIG_PATH_REQUIRED"
    );
  }

  const document =
    JSON.parse(
      fs.readFileSync(
        configPath,
        "utf8"
      )
    );

  /*
   * Accept either:
   * 1) connectivity-only document:
   *    { driverId, source }
   *
   * or
   *
   * 2) full connector config with .source
   *
   * No connector token is required because
   * backend transport is outside this authority.
   */
  if (
    s(document.driverId) !==
    "mysql"
  ) {
    throw new Error(
      `UNSUPPORTED_CONNECTIVITY_DRIVER:${s(document.driverId)}`
    );
  }

  const result =
    await checkMySqlSourceConnectivity(
      document.source,
      {
        env: process.env
      }
    );

  console.log(
    JSON.stringify(
      result,
      null,
      2
    )
  );
}

main().catch((err) => {
  console.error(
    JSON.stringify(
      {
        ok: false,
        code:
          String(
            err?.code ||
            err?.message ||
            "SOURCE_CONNECTIVITY_FAILED"
          ),
        message:
          String(
            err?.message ||
            "Source connectivity failed"
          )
      },
      null,
      2
    )
  );

  process.exit(1);
});
