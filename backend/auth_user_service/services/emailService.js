//
// backend/auth_user_service/services/emailService.js
//
// ✅ PRODUCTION EMAIL SERVICE
// ✅ Supports Brevo Transactional Email API over HTTPS
// ✅ Avoids SMTP ports blocked on Render Free
// ✅ Keeps the same public functions used by auth controllers:
//    - isEmailConfigured()
//    - maskEmail()
//    - sendPasswordResetOtpEmail()
//    - sendRecoveryEmailOtpEmail()
//
// Required Render env for Brevo:
//   EMAIL_PROVIDER=brevo
//   BREVO_API_KEY=xxxxxxxxxxxxxxxx
//   EMAIL_FROM=Clinic Smart Staff <admin@smf-clinic-systems.com>
//   APP_NAME=Clinic Smart Staff
//   RESET_LOG=false
//

const https = require("https");

function s(v) {
  return String(v || "").trim();
}

function b(v, fallback = false) {
  const x = String(v ?? "").trim().toLowerCase();
  if (!x) return fallback;
  return ["true", "1", "yes", "y", "on"].includes(x);
}

function n(v, fallback) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function provider() {
  return s(process.env.EMAIL_PROVIDER || "brevo").toLowerCase();
}

function isBrevoConfigured() {
  return !!(
    provider() === "brevo" &&
    s(process.env.BREVO_API_KEY) &&
    s(process.env.EMAIL_FROM)
  );
}

function isEmailConfigured() {
  return isBrevoConfigured();
}

function maskEmail(email) {
  const v = s(email);
  const [name, domain] = v.split("@");
  if (!name || !domain) return "";
  const visible = name.length <= 2 ? name[0] || "*" : name.slice(0, 2);
  return `${visible}***@${domain}`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function parseSender(rawFrom) {
  const appName = s(process.env.APP_NAME || "Clinic Smart Staff");
  const from = s(rawFrom || process.env.EMAIL_FROM);

  // Supports: Clinic Smart Staff <admin@smf-clinic-systems.com>
  const match = from.match(/^(.*?)<([^>]+)>$/);

  if (match) {
    const name = s(match[1]).replace(/^"|"$/g, "") || appName;
    const email = s(match[2]);
    return { name, email };
  }

  return {
    name: appName,
    email: from,
  };
}

function buildOtpEmailHtml({
  appName,
  heading,
  intro,
  otp,
  expiresInMinutes,
}) {
  const safeApp = escapeHtml(appName);
  const safeHeading = escapeHtml(heading);
  const safeIntro = escapeHtml(intro);
  const safeOtp = escapeHtml(otp);
  const safeMinutes = escapeHtml(expiresInMinutes);

  return `
    <div style="margin:0;padding:0;background:#f6f7fb;">
      <div style="max-width:560px;margin:0 auto;padding:24px;">
        <div style="background:#ffffff;border-radius:14px;padding:28px;font-family:Arial,'Helvetica Neue',sans-serif;line-height:1.6;color:#111827;border:1px solid #e5e7eb;">
          <div style="font-size:14px;color:#16a34a;font-weight:700;margin-bottom:8px;">
            ${safeApp}
          </div>

          <h2 style="margin:0 0 12px;font-size:22px;color:#111827;">
            ${safeHeading}
          </h2>

          <p style="margin:0 0 16px;font-size:15px;color:#374151;">
            ${safeIntro}
          </p>

          <div style="font-size:32px;font-weight:800;letter-spacing:6px;margin:20px 0;padding:18px 16px;text-align:center;background:#f3f4f6;border-radius:12px;color:#111827;">
            ${safeOtp}
          </div>

          <p style="margin:0 0 8px;font-size:14px;color:#374151;">
            รหัสนี้จะหมดอายุภายใน <b>${safeMinutes} นาที</b>
          </p>

          <p style="margin:14px 0 0;font-size:13px;color:#6b7280;">
            หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ
          </p>
        </div>

        <p style="font-family:Arial,'Helvetica Neue',sans-serif;text-align:center;font-size:12px;color:#9ca3af;margin-top:16px;">
          This is an automated security email from ${safeApp}.
        </p>
      </div>
    </div>
  `;
}

function postJsonViaHttps({ hostname, path, headers, body, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);

    const req = https.request(
      {
        hostname,
        path,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "Content-Length": Buffer.byteLength(payload),
          ...headers,
        },
        timeout: timeoutMs,
      },
      (res) => {
        let data = "";

        res.setEncoding("utf8");

        res.on("data", (chunk) => {
          data += chunk;
        });

        res.on("end", () => {
          let parsed = null;

          try {
            parsed = data ? JSON.parse(data) : null;
          } catch (_) {
            parsed = { raw: data };
          }

          resolve({
            statusCode: res.statusCode || 0,
            headers: res.headers || {},
            body: parsed,
          });
        });
      }
    );

    req.on("timeout", () => {
      req.destroy(new Error("Brevo API request timeout"));
    });

    req.on("error", reject);

    req.write(payload);
    req.end();
  });
}

async function sendBrevoTransactionalEmail({
  to,
  subject,
  text,
  html,
  type = "email",
}) {
  const email = s(to);

  if (!email) {
    return { ok: false, reason: "missing_email" };
  }

  if (!isBrevoConfigured()) {
    return { ok: false, reason: "email_not_configured" };
  }

  const sender = parseSender(process.env.EMAIL_FROM);

  if (!sender.email || !sender.email.includes("@")) {
    return { ok: false, reason: "invalid_email_from" };
  }

  const body = {
    sender,
    to: [{ email }],
    subject: s(subject),
    textContent: s(text),
    htmlContent: s(html),
  };

  const timeoutMs = n(process.env.BREVO_TIMEOUT_MS, 12000);

  const res = await postJsonViaHttps({
    hostname: "api.brevo.com",
    path: "/v3/smtp/email",
    timeoutMs,
    headers: {
      "api-key": s(process.env.BREVO_API_KEY),
    },
    body,
  });

  if (res.statusCode < 200 || res.statusCode >= 300) {
    const code = s(res.body?.code);
    const message = s(res.body?.message || res.body?.raw || "unknown_error");

    console.error("📧 Brevo send failed:", {
      statusCode: res.statusCode,
      code,
      message,
      type,
      to: maskEmail(email),
    });

    throw new Error(
      `Brevo send failed: HTTP ${res.statusCode}${code ? ` ${code}` : ""}`
    );
  }

  const messageId = s(res.body?.messageId);

  console.log("📧 Brevo email sent:", {
    type,
    to: maskEmail(email),
    messageId: messageId || undefined,
  });

  return {
    ok: true,
    to: maskEmail(email),
    provider: "brevo",
    messageId: messageId || undefined,
  };
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

  const appName = s(process.env.APP_NAME || "Clinic Smart Staff");
  const subject = `รหัสยืนยันการตั้งรหัสผ่านใหม่ - ${appName}`;

  const text = [
    `รหัสยืนยันการตั้งรหัสผ่านใหม่ของคุณคือ: ${otp}`,
    ``,
    `รหัสนี้จะหมดอายุภายใน ${expiresInMinutes} นาที`,
    `หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ`,
  ].join("\n");

  const html = buildOtpEmailHtml({
    appName,
    heading: "รหัสยืนยันการตั้งรหัสผ่านใหม่",
    intro: "ใช้รหัสด้านล่างเพื่อยืนยันการตั้งรหัสผ่านใหม่ของบัญชีคุณ",
    otp,
    expiresInMinutes,
  });

  return sendBrevoTransactionalEmail({
    to: email,
    subject,
    text,
    html,
    type: "password_reset_otp",
  });
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

  const appName = s(process.env.APP_NAME || "Clinic Smart Staff");
  const subject = `รหัสยืนยันอีเมลกู้คืนบัญชี - ${appName}`;

  const text = [
    `รหัสยืนยันอีเมลกู้คืนบัญชีของคุณคือ: ${otp}`,
    ``,
    `รหัสนี้จะหมดอายุภายใน ${expiresInMinutes} นาที`,
    `หากคุณไม่ได้เป็นผู้ร้องขอ กรุณาไม่ต้องดำเนินการใด ๆ`,
  ].join("\n");

  const html = buildOtpEmailHtml({
    appName,
    heading: "รหัสยืนยันอีเมลกู้คืนบัญชี",
    intro: "ใช้รหัสด้านล่างเพื่อยืนยันอีเมลกู้คืนบัญชีของคุณ",
    otp,
    expiresInMinutes,
  });

  return sendBrevoTransactionalEmail({
    to: email,
    subject,
    text,
    html,
    type: "recovery_email_otp",
  });
}

module.exports = {
  isEmailConfigured,
  maskEmail,
  sendPasswordResetOtpEmail,
  sendRecoveryEmailOtpEmail,
};
