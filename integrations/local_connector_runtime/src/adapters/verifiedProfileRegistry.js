"use strict";

const {
  FD_OBSERVED_XFER_SOURCE_PROFILE,
} = require("./fd/observedXferSourceProfile");

function s(value) {
  return String(value ?? "").trim();
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function deepFreeze(value) {
  if (!value || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }

  for (const child of Object.values(value)) {
    deepFreeze(child);
  }

  return Object.freeze(value);
}

function normalizeDefinition(definition = {}) {
  const profileId = s(definition.profileId);
  const adapterId = s(definition.adapterId);
  const driverId = s(definition.driverId);
  const database = s(definition.source?.database);
  const poll = definition.source?.poll;
  const adapterProfile = definition.adapterProfile;

  if (!profileId) throw new Error("VERIFIED_PROFILE_ID_REQUIRED");
  if (!adapterId) throw new Error("VERIFIED_PROFILE_ADAPTER_ID_REQUIRED");
  if (!driverId) throw new Error("VERIFIED_PROFILE_DRIVER_ID_REQUIRED");
  if (!database) throw new Error("VERIFIED_PROFILE_DATABASE_REQUIRED");
  if (!poll || typeof poll !== "object" || Array.isArray(poll)) {
    throw new Error("VERIFIED_PROFILE_POLL_REQUIRED");
  }
  if (!adapterProfile || typeof adapterProfile !== "object" || Array.isArray(adapterProfile)) {
    throw new Error("VERIFIED_PROFILE_ADAPTER_PROFILE_REQUIRED");
  }
  if (adapterProfile.schemaVerified !== true) {
    throw new Error("VERIFIED_PROFILE_SCHEMA_VERIFICATION_REQUIRED");
  }
  if (adapterProfile.movementSemanticsVerified !== true) {
    throw new Error("VERIFIED_PROFILE_MOVEMENT_SEMANTICS_REQUIRED");
  }

  return deepFreeze(clone({
    profileId,
    adapterId,
    driverId,
    source: { database, poll },
    adapterProfile,
  }));
}

class VerifiedProfileRegistry {
  constructor() {
    this.profiles = new Map();
  }

  register(definition) {
    const normalized = normalizeDefinition(definition);
    const key = `${normalized.adapterId}:${normalized.profileId}`;

    if (this.profiles.has(key)) {
      throw new Error(`VERIFIED_PROFILE_ALREADY_REGISTERED:${key}`);
    }

    this.profiles.set(key, normalized);
    return normalized;
  }

  get(adapterId, profileId) {
    const key = `${s(adapterId)}:${s(profileId)}`;
    const profile = this.profiles.get(key);

    if (!profile) {
      throw new Error(`VERIFIED_PROFILE_NOT_FOUND:${key}`);
    }

    return profile;
  }

  list() {
    return [...this.profiles.keys()].sort();
  }
}

function fdDefinition() {
  const profile = FD_OBSERVED_XFER_SOURCE_PROFILE;

  if (profile.production?.adapterActivationAllowed !== true) {
    throw new Error("FD_VERIFIED_PROFILE_NOT_ACTIVATABLE");
  }

  return {
    profileId: profile.id,
    adapterId: "fd",
    driverId: profile.source.engine,
    source: {
      database: profile.source.database,
      poll: profile.source.poll,
    },
    adapterProfile: profile.adapterProfile,
  };
}

function createDefaultVerifiedProfileRegistry() {
  const registry = new VerifiedProfileRegistry();
  registry.register(fdDefinition());
  return registry;
}

const DEFAULT_VERIFIED_PROFILE_REGISTRY =
  createDefaultVerifiedProfileRegistry();

module.exports = {
  VerifiedProfileRegistry,
  createDefaultVerifiedProfileRegistry,
  DEFAULT_VERIFIED_PROFILE_REGISTRY,
};
