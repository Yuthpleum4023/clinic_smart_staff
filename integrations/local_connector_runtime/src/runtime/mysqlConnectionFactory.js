"use strict";

async function mysqlConnectionFactory(config, deps = {}) {
  let mysql;

  try {
    mysql = deps.mysqlModule || require("mysql2/promise");
  } catch (err) {
    const wrapped = new Error(
      "MYSQL2_DEPENDENCY_REQUIRED_FOR_MYSQL_DRIVER"
    );
    wrapped.code = "MYSQL2_DEPENDENCY_REQUIRED";
    wrapped.cause = err;
    throw wrapped;
  }

  const connection = await mysql.createConnection({
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    multipleStatements: false,
    connectTimeout: 10000,
    enableKeepAlive: true
  });

  if (
    !connection ||
    typeof connection.query !== "function" ||
    typeof connection.end !== "function"
  ) {
    throw new Error("MYSQL_CONNECTION_CONTRACT_INVALID");
  }

  /*
   * Use mysql2's text protocol deliberately. SQL structure is produced only
   * from the read-only poll contract and values remain mysql2-bound. Avoiding
   * server prepared statements preserves compatibility with verified legacy
   * MySQL sources while multipleStatements remains disabled.
   */
  return {
    async query(sql, values = []) {
      return connection.query(sql, values);
    },

    async ping() {
      if (typeof connection.ping === "function") {
        return connection.ping();
      }
    },

    async end() {
      return connection.end();
    }
  };
}

module.exports = { mysqlConnectionFactory };
