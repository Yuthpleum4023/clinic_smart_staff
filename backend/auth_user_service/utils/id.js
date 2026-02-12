// utils/id.js

function makeId(prefix = "", len = 10) {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  let out = prefix;
  for (let i = 0; i < len; i++) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}

function makeInviteCode(len = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // ไม่มี O,0,I,1 กันสับสน
  let out = "";
  for (let i = 0; i < len; i++) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}

module.exports = {
  makeId,
  makeInviteCode,
};
