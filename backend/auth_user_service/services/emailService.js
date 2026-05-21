const nodemailer = require("nodemailer");
const dns = require("dns");

try {
  dns.setDefaultResultOrder("ipv4first");
} catch (_) {
  // Node versions without setDefaultResultOrder can safely ignore this.
}

function s(v) {
  return String(v || "").trim();
}

function b(v, fallback = false) {
  const x = String(v ?? "").trim().toLowerCase();
  if (!x) return fallback;
  return ["true", "1", "yes", "y"].includes(x);
}

function n(v, fallback) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function isEmailConfigured() {
  return !!(
    s(process.env.SMTP_HOST) &&
    s(process.env.SMTP_USER) &&
    s(process.env.SMTP_PASS) &&
    s(process.env.EMAIL_FROM)
  );
}

function maskEmail(email) {
  const v = s(email);
  const [name, domain] = v.split("@");
  if (!name || !domain) return "";
  const visible = name.length <= 2 ? name[0] || "*" : name.slice(0, 2);
  return `${visible}***@${domain}`;
}

function makeTransporter() {
  const port = n(process.env.SMTP_PORT, 587);
  const secure = b(process.env.SMTP_SECURE, port === 465);

  return nodemailer.createTransport({
    host: s(process.env.SMTP_HOST),
    port,
    secure,

    // Render may fail when Node tries Gmail SMTP over IPv6.
    // Force IPv4 and fail faster than the service-level request timeout.
    family: 4,
    connectionTimeout: n(process.env.SMTP_CONNECTION_TIMEOUT_MS, 8000),
    greetingTimeout: n(process.env.SMTP_GREETING_TIMEOUT_MS, 8000),
    socketTimeout: n(process.env.SMTP_SOCKET_TIMEOUT_MS, 10000),

    // Force DNS lookup to IPv4 because Render may not reach Gmail SMTP over IPv6.
    lookup: (hostname, options, callback) => {
      dns.lookup(hostname, { family: 4 }, callback);
    },

    auth: {
      user: s(process.env.SMTP_USER),
      pass: s(process.env.SMTP_PASS),
    },
  });
}

async function sendPasswordResetOtpEmail({
  to,
  code,
  expiresInMinutes = 10,
}) {
  const email = s(to);
  const otp = s(code);

  if (!email || !otp) {
    return { ok: false, reason: "missing_email_or_code" };
  }

  if (!isEmailConfigured()) {
    return { ok: false, reason: "email_not_configured" };
  }

  const from = s(process.env.EMAIL_FROM);
  const appName = s(process.env.APP_NAME || "Clinic Smart Staff");

  const subject = `รหัสยืนยันการตั้งรหัสผ่านใหม่ - ${appName}`;

  const text = [
    `รหัสยืนยันการตั้งรหัสผ่านใหม่ของคุณคือ: ${otp}`,
    ``,
    `รหัสนี้จะหมดอายุภายใน ${expiresInMinutes} นาที`,
    `หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ`,
  ].join("\n");

  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.6;color:#111">
      <h2>${appName}</h2>
      <p>รหัสยืนยันการตั้งรหัสผ่านใหม่ของคุณคือ</p>
      <div style="font-size:28px;font-weight:bold;letter-spacing:4px;margin:16px 0">
        ${otp}
      </div>
      <p>รหัสนี้จะหมดอายุภายใน <b>${expiresInMinutes} นาที</b></p>
      <p style="color:#555">หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ</p>
    </div>
  `;

  const transporter = makeTransporter();

  await transporter.sendMail({
    from,
    to: email,
    subject,
    text,
    html,
  });

  return { ok: true, to: maskEmail(email) };
}

async function sendRecoveryEmailOtpEmail({
  to,
  code,
  expiresInMinutes = 10,
}) {
  const email = s(to);
  const otp = s(code);

  if (!email || !otp) {
    return { ok: false, reason: "missing_email_or_code" };
  }

  if (!isEmailConfigured()) {
    return { ok: false, reason: "email_not_configured" };
  }

  const from = s(process.env.EMAIL_FROM);
  const appName = s(process.env.APP_NAME || "Clinic Smart Staff");

  const subject = `รหัสยืนยันอีเมลกู้คืนบัญชี - ${appName}`;

  const text = [
    `รหัสยืนยันอีเมลกู้คืนบัญชีของคุณคือ: ${otp}`,
    ``,
    `รหัสนี้จะหมดอายุภายใน ${expiresInMinutes} นาที`,
    `หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ`,
  ].join("\n");

  const html = `
    <div style="font-family:Arial,sans-serif;line-height:1.6;color:#111">
      <h2>${appName}</h2>
      <p>รหัสยืนยันอีเมลกู้คืนบัญชีของคุณคือ</p>
      <div style="font-size:28px;font-weight:bold;letter-spacing:4px;margin:16px 0">
        ${otp}
      </div>
      <p>รหัสนี้จะหมดอายุภายใน <b>${expiresInMinutes} นาที</b></p>
      <p style="color:#555">หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ</p>
    </div>
  `;

  const transporter = makeTransporter();

  await transporter.sendMail({
    from,
    to: email,
    subject,
    text,
    html,
  });

  return { ok: true, to: maskEmail(email) };
}

module.exports = {
  isEmailConfigured,
  maskEmail,
  sendPasswordResetOtpEmail,
  sendRecoveryEmailOtpEmail,
};
