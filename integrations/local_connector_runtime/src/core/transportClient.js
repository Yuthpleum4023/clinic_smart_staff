"use strict";

function s(v) {
  return String(v ?? "").trim();
}

class InventoryIngestionClient {
  constructor({
    baseUrl,
    connectorToken,
    fetchImpl = globalThis.fetch
  }) {
    this.baseUrl =
      s(baseUrl).replace(/\/+$/, "");
    this.connectorToken = s(connectorToken);
    this.fetchImpl = fetchImpl;

    if (!this.baseUrl) {
      throw new Error("BASE_URL_REQUIRED");
    }

    if (!this.connectorToken) {
      throw new Error(
        "CONNECTOR_TOKEN_REQUIRED"
      );
    }

    if (
      typeof this.fetchImpl !== "function"
    ) {
      throw new Error(
        "FETCH_IMPLEMENTATION_REQUIRED"
      );
    }
  }

  async postEvent(path, event) {
    const response =
      await this.fetchImpl(
        `${this.baseUrl}${path}`,
        {
          method: "POST",
          headers: {
            authorization:
              `Bearer ${this.connectorToken}`,
            "content-type":
              "application/json"
          },
          body: JSON.stringify(event)
        }
      );

    const text = await response.text();
    let body = {};

    try {
      body = text
        ? JSON.parse(text)
        : {};
    } catch (_) {
      body = { raw: text };
    }

    if (!response.ok) {
      const err = new Error(
        body?.message ||
          `Ingestion HTTP ${response.status}`
      );
      err.status = response.status;
      err.code =
        body?.code ||
        "INGESTION_HTTP_ERROR";
      throw err;
    }

    return body;
  }

  async sendMovement(event) {
    return this.postEvent(
      "/api/inventory/integrations/movements",
      event
    );
  }

  // Backward-compatible transport for existing
  // consumption-only runtime callers.
  async sendConsumption(event) {
    return this.postEvent(
      "/api/inventory/integrations/consumption",
      event
    );
  }
}

module.exports = {
  InventoryIngestionClient
};
