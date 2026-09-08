"use strict";

async function mysqlConnectionFactory(config) {
  let mysql;

  try {
    mysql = require("mysql2/promise");
  } catch (err) {
    const wrapped = new Error(
      "MYSQL2_DEPENDENCY_REQUIRED_FOR_MYSQL_DRIVER"
    );
    wrapped.code = "MYSQL2_DEPENDENCY_REQUIRED";
    wrapped.cause = err;
    throw wrapped;
  }

  return mysql.createConnection({
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    multipleStatements: false,
    connectTimeout: 10000,
    enableKeepAlive: true
  });
}

module.exports = { mysqlConnectionFactory };
