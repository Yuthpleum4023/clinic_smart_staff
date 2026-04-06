const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const http = require("http");
const https = require("https");
const PDFDocument = require("pdfkit");

function s(v) {
  return String(v || "").trim();
}

function n(v, fallback = 0) {
  const x = Number(v);
  return Number.isFinite(x) ? x : fallback;
}

function round2(v) {
  const x = Number(v || 0);
  return Number.isFinite(x) ? Math.round(x * 100) / 100 : 0;
}

function formatAmount(v) {
  return round2(v).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function formatThaiDate(dateInput) {
  const d = new Date(dateInput);
  if (Number.isNaN(d.getTime())) return "-";

  const day = d.getDate();
  const monthNames = [
    "มกราคม",
    "กุมภาพันธ์",
    "มีนาคม",
    "เมษายน",
    "พฤษภาคม",
    "มิถุนายน",
    "กรกฎาคม",
    "สิงหาคม",
    "กันยายน",
    "ตุลาคม",
    "พฤศจิกายน",
    "ธันวาคม",
  ];
  const month = monthNames[d.getMonth()] || "";
  const year = d.getFullYear() + 543;

  return `${day} ${month} ${year}`;
}

function ensureDirSync(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function fileExists(p) {
  try {
    return !!p && fs.existsSync(p);
  } catch (_) {
    return false;
  }
}

function safeFileNamePart(v) {
  return s(v).replace(/[^a-zA-Z0-9ก-๙._-]+/g, "_");
}

function getStorageRoot() {
  return (
    s(process.env.SOCIAL_SECURITY_RECEIPT_STORAGE_DIR) ||
    path.join(process.cwd(), "uploads", "social-security-receipts")
  );
}

function getBasePublicUrl() {
  return s(process.env.PUBLIC_BASE_URL);
}

function buildPublicUrl(fileName) {
  const base = getBasePublicUrl();
  if (!base) return "";
  return `${base.replace(/\/+$/, "")}/social-security-receipts-files/${encodeURIComponent(
    fileName
  )}`;
}

function resolveFontPath(envKey, fallbackCandidates = []) {
  const envPath = s(process.env[envKey]);
  if (envPath && fileExists(envPath)) return envPath;

  for (const p of fallbackCandidates) {
    if (fileExists(p)) return p;
  }
  return "";
}

function getFontPaths() {
  const base = process.cwd();

  const regular = resolveFontPath("PDF_FONT_REGULAR_PATH", [
    path.join(base, "assets", "fonts", "NotoSansThai-Regular.ttf"),
    path.join(base, "assets", "fonts", "NotoSansThai_Condensed-Regular.ttf"),
    path.join(base, "fonts", "NotoSansThai-Regular.ttf"),
    path.join(base, "fonts", "NotoSansThai_Condensed-Regular.ttf"),
    path.join(base, "public", "fonts", "NotoSansThai-Regular.ttf"),
    path.join(base, "public", "fonts", "NotoSansThai_Condensed-Regular.ttf"),
  ]);

  const bold = resolveFontPath("PDF_FONT_BOLD_PATH", [
    path.join(base, "assets", "fonts", "NotoSansThai-Bold.ttf"),
    path.join(base, "assets", "fonts", "NotoSansThai_Condensed-Bold.ttf"),
    path.join(base, "fonts", "NotoSansThai-Bold.ttf"),
    path.join(base, "fonts", "NotoSansThai_Condensed-Bold.ttf"),
    path.join(base, "public", "fonts", "NotoSansThai-Bold.ttf"),
    path.join(base, "public", "fonts", "NotoSansThai_Condensed-Bold.ttf"),
  ]);

  return { regular, bold };
}

function canRegisterFont(fontPath) {
  try {
    if (!fontPath || !fileExists(fontPath)) return false;
    const stat = fs.statSync(fontPath);
    return stat.isFile() && stat.size > 0;
  } catch (_) {
    return false;
  }
}

function applyFonts(doc) {
  const fonts = getFontPaths();

  let regularName = "Helvetica";
  let boldName = "Helvetica-Bold";

  try {
    if (canRegisterFont(fonts.regular)) {
      doc.registerFont("TH", fonts.regular);
      regularName = "TH";
    }
  } catch (_) {}

  try {
    if (canRegisterFont(fonts.bold)) {
      doc.registerFont("THB", fonts.bold);
      boldName = "THB";
    } else if (regularName === "TH") {
      boldName = "TH";
    }
  } catch (_) {
    if (regularName === "TH") {
      boldName = "TH";
    }
  }

  return {
    regular: regularName,
    bold: boldName,
  };
}

function setFont(doc, fontName, size = 11) {
  return doc.font(fontName).fontSize(size);
}

function getValueDeep(obj, pathText, fallback = "") {
  const parts = String(pathText || "").split(".");
  let cur = obj;
  for (const part of parts) {
    if (!cur || typeof cur !== "object") return fallback;
    cur = cur[part];
  }
  return cur == null ? fallback : cur;
}

function pickFirst(...values) {
  for (const value of values) {
    const text = s(value);
    if (text) return text;
  }
  return "";
}

function textHeight(doc, text, options = {}) {
  const {
    width = 100,
    fontName = "Helvetica",
    fontSize = 10,
    lineGap = 0,
  } = options;

  const safeText = s(text) || " ";
  setFont(doc, fontName, fontSize);
  return Math.ceil(
    doc.heightOfString(safeText, {
      width,
      lineGap,
      align: "left",
    })
  );
}

async function downloadToBuffer(url) {
  return new Promise((resolve, reject) => {
    const safeUrl = s(url);
    if (!safeUrl) {
      return reject(new Error("logo url is empty"));
    }

    const client = safeUrl.startsWith("https://") ? https : http;

    client
      .get(safeUrl, (res) => {
        if (
          [301, 302, 303, 307, 308].includes(res.statusCode) &&
          res.headers.location
        ) {
          return resolve(downloadToBuffer(res.headers.location));
        }

        if (res.statusCode !== 200) {
          return reject(
            new Error(`failed to fetch logo, status=${res.statusCode}`)
          );
        }

        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => resolve(Buffer.concat(chunks)));
      })
      .on("error", reject);
  });
}

async function resolveLogoBuffer(logoUrlOrPath) {
  const src = s(logoUrlOrPath);
  if (!src) return null;

  try {
    if (src.startsWith("http://") || src.startsWith("https://")) {
      return await downloadToBuffer(src);
    }

    const abs = path.isAbsolute(src) ? src : path.join(process.cwd(), src);
    if (fileExists(abs)) {
      return await fsp.readFile(abs);
    }

    return null;
  } catch (_) {
    return null;
  }
}

function drawBorder(doc, x, y, w, h) {
  doc.rect(x, y, w, h).stroke();
}

function drawTextBox(doc, { x, y, w, h, label, value, fontRegular, fontBold }) {
  drawBorder(doc, x, y, w, h);

  setFont(doc, fontBold, 8.5);
  doc.text(s(label), x + 6, y + 3, {
    width: w - 12,
    align: "left",
    lineGap: 0,
    ellipsis: true,
  });

  setFont(doc, fontRegular, 9.6);
  doc.text(s(value), x + 6, y + 16, {
    width: w - 12,
    align: "left",
    lineGap: 0,
    ellipsis: true,
  });
}

function drawCompactTextBox(
  doc,
  { x, y, w, h, label, value, fontRegular, fontBold }
) {
  drawBorder(doc, x, y, w, h);

  setFont(doc, fontBold, 8.5);
  doc.text(s(label), x + 6, y + 4, {
    width: w - 12,
    align: "left",
    lineGap: 0,
    ellipsis: true,
  });

  setFont(doc, fontRegular, 9.4);
  doc.text(s(value), x + 6, y + 15, {
    width: w - 12,
    align: "left",
    lineGap: 0,
    ellipsis: true,
  });
}

function getKeyValueRowHeight(doc, row, options = {}) {
  const {
    width = 515,
    labelWidth = 130,
    minHeight = 26,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
    fontSize = 9.2,
    lineGap = 1,
  } = options;

  const labelH = textHeight(doc, s(row.label), {
    width: labelWidth - 12,
    fontName: fontBold,
    fontSize,
    lineGap,
  });

  const valueH = textHeight(doc, s(row.value) || "-", {
    width: width - labelWidth - 16,
    fontName: fontRegular,
    fontSize,
    lineGap,
  });

  return Math.max(minHeight, row.height || 0, labelH + 10, valueH + 10);
}

function drawKeyValueRows(doc, rows, options = {}) {
  const {
    x = 40,
    y = 40,
    width = 515,
    rowHeight = 26,
    labelWidth = 130,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  let cursorY = y;

  rows.forEach((row) => {
    const h = getKeyValueRowHeight(doc, row, {
      width,
      labelWidth,
      minHeight: rowHeight,
      fontRegular,
      fontBold,
    });

    drawBorder(doc, x, cursorY, width, h);
    drawBorder(doc, x, cursorY, labelWidth, h);

    setFont(doc, fontBold, 9.2);
    doc.text(s(row.label), x + 6, cursorY + 5, {
      width: labelWidth - 12,
      align: "left",
      lineGap: 1,
    });

    setFont(doc, fontRegular, 9.2);
    doc.text(s(row.value) || "-", x + labelWidth + 8, cursorY + 5, {
      width: width - labelWidth - 16,
      align: "left",
      lineGap: 1,
    });

    cursorY += h;
  });

  return cursorY;
}

function drawCheckBox(doc, { x, y, size = 10, checked = false }) {
  doc.rect(x, y, size, size).stroke();
  if (checked) {
    doc
      .moveTo(x + 2, y + size / 2)
      .lineTo(x + 4, y + size - 2)
      .lineTo(x + size - 2, y + 2)
      .stroke();
  }
}

function getItemRowHeight(doc, item, width, fontRegular) {
  if (!item) return 28;

  const descHeight = textHeight(doc, s(item.description) || "-", {
    width,
    fontName: fontRegular,
    fontSize: 8.6,
    lineGap: 0.8,
  });

  return Math.max(28, descHeight + 10);
}

function drawItemsTable(doc, items, options = {}) {
  const {
    x = 40,
    y = 250,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  const colNo = 28;
  const colDesc = 180;
  const colQty = 40;
  const colUnit = 55;
  const colGross = 68;
  const colWht = 68;
  const colNet = 76;

  const tableWidth =
    colNo + colDesc + colQty + colUnit + colGross + colWht + colNet;
  const headerHeight = 34;
  const totalRows = Math.max(5, Array.isArray(items) ? items.length : 0);

  const xs = [
    x,
    x + colNo,
    x + colNo + colDesc,
    x + colNo + colDesc + colQty,
    x + colNo + colDesc + colQty + colUnit,
    x + colNo + colDesc + colQty + colUnit + colGross,
    x + colNo + colDesc + colQty + colUnit + colGross + colWht,
    x + tableWidth,
  ];

  drawBorder(doc, x, y, tableWidth, headerHeight);
  for (let i = 1; i < xs.length - 1; i += 1) {
    doc.moveTo(xs[i], y).lineTo(xs[i], y + headerHeight).stroke();
  }

  setFont(doc, fontBold, 8.1);
  const headerY = y + 7;

  doc.text("ลำดับ", x + 2, headerY, {
    width: colNo - 4,
    align: "center",
    lineGap: 0.5,
  });

  doc.text("รายการ", x + colNo + 4, headerY, {
    width: colDesc - 8,
    align: "center",
    lineGap: 0.5,
  });

  doc.text("จำนวน", x + colNo + colDesc + 3, headerY, {
    width: colQty - 6,
    align: "center",
    lineGap: 0.5,
  });

  doc.text("หน่วยละ", x + colNo + colDesc + colQty + 3, headerY, {
    width: colUnit - 6,
    align: "center",
    lineGap: 0.5,
  });

  doc.text("จำนวนเงิน", x + colNo + colDesc + colQty + colUnit + 3, headerY, {
    width: colGross - 6,
    align: "center",
    lineGap: 0.5,
  });

  doc.text(
    "ภาษีหัก\nณ ที่จ่าย",
    x + colNo + colDesc + colQty + colUnit + colGross + 3,
    y + 4,
    {
      width: colWht - 6,
      align: "center",
      lineGap: 0.8,
    }
  );

  doc.text(
    "สุทธิ",
    x + colNo + colDesc + colQty + colUnit + colGross + colWht + 3,
    headerY,
    {
      width: colNet - 6,
      align: "center",
      lineGap: 0.5,
    }
  );

  let cursorY = y + headerHeight;

  for (let i = 0; i < totalRows; i += 1) {
    const item = Array.isArray(items) ? items[i] : null;
    const rowHeight = getItemRowHeight(doc, item, colDesc - 8, fontRegular);

    drawBorder(doc, x, cursorY, tableWidth, rowHeight);
    for (let c = 1; c < xs.length - 1; c += 1) {
      doc.moveTo(xs[c], cursorY).lineTo(xs[c], cursorY + rowHeight).stroke();
    }

    const rowTextY = cursorY + 5;
    setFont(doc, fontRegular, 8.6);

    doc.text(item ? String(i + 1) : "", x + 2, rowTextY, {
      width: colNo - 4,
      align: "center",
      lineGap: 0.5,
    });

    doc.text(item ? s(item.description) : "", x + colNo + 4, rowTextY, {
      width: colDesc - 8,
      align: "left",
      lineGap: 0.8,
    });

    doc.text(
      item ? formatAmount(n(item.quantity, 0)) : "",
      x + colNo + colDesc + 3,
      rowTextY,
      {
        width: colQty - 6,
        align: "right",
        lineGap: 0.5,
      }
    );

    doc.text(
      item ? formatAmount(n(item.unitPrice, 0)) : "",
      x + colNo + colDesc + colQty + 3,
      rowTextY,
      {
        width: colUnit - 6,
        align: "right",
        lineGap: 0.5,
      }
    );

    doc.text(
      item ? formatAmount(n(item.amount, 0)) : "",
      x + colNo + colDesc + colQty + colUnit + 3,
      rowTextY,
      {
        width: colGross - 6,
        align: "right",
        lineGap: 0.5,
      }
    );

    doc.text(
      item ? formatAmount(n(item.withholdingTaxAmount, 0)) : "",
      x + colNo + colDesc + colQty + colUnit + colGross + 3,
      rowTextY,
      {
        width: colWht - 6,
        align: "right",
        lineGap: 0.5,
      }
    );

    doc.text(
      item
        ? formatAmount(
            n(
              item.netAmount,
              Math.max(0, n(item.amount, 0) - n(item.withholdingTaxAmount, 0))
            )
          )
        : "",
      x + colNo + colDesc + colQty + colUnit + colGross + colWht + 3,
      rowTextY,
      {
        width: colNet - 6,
        align: "right",
        lineGap: 0.5,
      }
    );

    cursorY += rowHeight;
  }

  return cursorY;
}

function drawSummaryBox(doc, summary, options = {}) {
  const {
    x = 340,
    y = 460,
    width = 215,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  const rowH = 26;
  const labelW = 110;

  const rows = [
    { label: "รวมเป็นเงิน", value: formatAmount(summary.subtotal) },
    {
      label: "ภาษีหัก ณ ที่จ่าย",
      value: formatAmount(summary.withholdingTax),
    },
    {
      label: "จำนวนเงินสุทธิ",
      value: formatAmount(summary.netAmount),
      bold: true,
    },
  ];

  let cursorY = y;

  rows.forEach((row) => {
    drawBorder(doc, x, cursorY, width, rowH);
    drawBorder(doc, x, cursorY, labelW, rowH);

    setFont(doc, row.bold ? fontBold : fontRegular, row.bold ? 10 : 9.5);
    doc.text(s(row.label), x + 6, cursorY + 7, {
      width: labelW - 12,
      align: "left",
      lineGap: 1,
    });

    doc.text(s(row.value), x + labelW + 6, cursorY + 7, {
      width: width - labelW - 12,
      align: "right",
      lineGap: 1,
    });

    cursorY += rowH;
  });

  return cursorY;
}

function getPaymentAreaHeight(doc, data, options = {}) {
  const {
    width = 260,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  const paymentInfo = data.paymentInfo || {};
  const textWidth = width - 16;

  const titleH = textHeight(doc, "วิธีการชำระเงิน", {
    width: textWidth,
    fontName: fontBold,
    fontSize: 9.5,
    lineGap: 1,
  });

  const detailLines = [
    `ธนาคาร: ${pickFirst(paymentInfo.bankName, "-") || "-"}`,
    `ชื่อบัญชี: ${pickFirst(paymentInfo.accountName, "-") || "-"}`,
    `เลขบัญชี: ${pickFirst(paymentInfo.accountNumber, "-") || "-"}`,
    `อ้างอิง: ${pickFirst(paymentInfo.transferRef, paymentInfo.chequeNo, "-") || "-"}`,
  ];

  let total = 8 + titleH + 18;
  detailLines.forEach((line) => {
    total += textHeight(doc, line, {
      width: textWidth,
      fontName: fontRegular,
      fontSize: 8.7,
      lineGap: 1.2,
    });
    total += 3;
  });

  return Math.max(100, total + 8);
}

function drawPaymentMethodArea(doc, data, options = {}) {
  const {
    x = 40,
    y = 675,
    width = 260,
    height = 100,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  const paymentInfo = data.paymentInfo || {};
  const method = s(paymentInfo.method).toLowerCase();

  drawBorder(doc, x, y, width, height);

  setFont(doc, fontBold, 9.5);
  doc.text("วิธีการชำระเงิน", x + 8, y + 8, {
    width: width - 16,
    lineGap: 1,
  });

  const methods = [
    { key: "cash", label: "เงินสด" },
    { key: "transfer", label: "โอนเงิน" },
    { key: "cheque", label: "เช็ค" },
    { key: "other", label: "อื่น ๆ" },
  ];

  let cursorX = x + 8;
  const rowY = y + 26;

  methods.forEach((item, index) => {
    const blockW = index < 2 ? 62 : 55;
    drawCheckBox(doc, {
      x: cursorX,
      y: rowY + 1,
      size: 10,
      checked: method === item.key,
    });
    setFont(doc, fontRegular, 8.8);
    doc.text(item.label, cursorX + 14, rowY - 1, {
      width: blockW,
      lineGap: 0,
    });
    cursorX += blockW + 10;
  });

  const lines = [
    `ธนาคาร: ${pickFirst(paymentInfo.bankName, "-") || "-"}`,
    `ชื่อบัญชี: ${pickFirst(paymentInfo.accountName, "-") || "-"}`,
    `เลขบัญชี: ${pickFirst(paymentInfo.accountNumber, "-") || "-"}`,
    `อ้างอิง: ${pickFirst(paymentInfo.transferRef, paymentInfo.chequeNo, "-") || "-"}`,
  ];

  let textY = y + 45;
  lines.forEach((line) => {
    setFont(doc, fontRegular, 8.7);
    doc.text(line, x + 8, textY, {
      width: width - 16,
      lineGap: 1.2,
    });
    textY += textHeight(doc, line, {
      width: width - 16,
      fontName: fontRegular,
      fontSize: 8.7,
      lineGap: 1.2,
    }) + 3;
  });

  return y + height;
}

function drawSignatureArea(doc, data, options = {}) {
  const {
    x = 315,
    y = 675,
    width = 240,
    height = 100,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  drawBorder(doc, x, y, width, height);

  const clinicName = pickFirst(
    getValueDeep(data, "clinicSnapshot.clinicName"),
    getValueDeep(data, "clinicName"),
    "........................................"
  );

  setFont(doc, fontRegular, 9.25);
  doc.text(
    "ลงชื่อ ................................................................. ผู้รับเงิน",
    x + 12,
    y + 24,
    {
      width: width - 24,
      align: "left",
      lineGap: 1,
    }
  );

  doc.text(`( ${clinicName} )`, x + 24, y + 48, {
    width: width - 36,
    align: "left",
    lineGap: 1,
  });

  doc.text(`วันที่ ${formatThaiDate(data.issueDate)}`, x + 58, y + 72, {
    width: width - 70,
    align: "left",
    lineGap: 1,
  });
}

async function createPdfFileFromReceipt(receipt, opts = {}) {
  const data =
    typeof receipt?.toObject === "function" ? receipt.toObject() : receipt;
  if (!data) {
    throw new Error("receipt data is required");
  }

  const receiptNo = s(data.receiptNo);
  const clinicId = s(data.clinicId);

  if (!receiptNo) throw new Error("receiptNo is required");
  if (!clinicId) throw new Error("clinicId is required");

  const clinicName = pickFirst(
    getValueDeep(data, "clinicSnapshot.clinicName"),
    getValueDeep(data, "clinicName"),
    "ชื่อคลินิก"
  );
  const clinicBranchName = pickFirst(
    getValueDeep(data, "clinicSnapshot.clinicBranchName"),
    getValueDeep(data, "clinicBranchName")
  );
  const clinicAddress = pickFirst(
    getValueDeep(data, "clinicSnapshot.clinicAddress"),
    getValueDeep(data, "clinicAddress")
  );
  const clinicPhone = pickFirst(
    getValueDeep(data, "clinicSnapshot.clinicPhone"),
    getValueDeep(data, "clinicPhone")
  );
  const clinicTaxId = pickFirst(
    getValueDeep(data, "clinicSnapshot.clinicTaxId"),
    getValueDeep(data, "clinicTaxId"),
    getValueDeep(data, "clinicSnapshot.taxId")
  );
  const withholderTaxId = pickFirst(
    getValueDeep(data, "clinicSnapshot.withholderTaxId"),
    getValueDeep(data, "withholderTaxId")
  );

  const customerName = pickFirst(
    getValueDeep(data, "customerSnapshot.customerName"),
    getValueDeep(data, "customerName")
  );
  const customerAddress = pickFirst(
    getValueDeep(data, "customerSnapshot.customerAddress"),
    getValueDeep(data, "customerAddress")
  );
  const customerTaxId = pickFirst(
    getValueDeep(data, "customerSnapshot.customerTaxId"),
    getValueDeep(data, "customerTaxId")
  );

  const storageRoot = getStorageRoot();
  ensureDirSync(storageRoot);

  const fileName =
    safeFileNamePart(
      opts.fileName || `${receiptNo}_${clinicId}_${Date.now()}.pdf`
    ) || `receipt_${Date.now()}.pdf`;

  const pdfPath = path.join(storageRoot, fileName);
  const pdfUrl = buildPublicUrl(fileName);

  const doc = new PDFDocument({
    size: "A4",
    margin: 36,
    compress: true,
    info: {
      Title: `Social Security Receipt ${receiptNo}`,
      Author: "payroll_service",
      Subject: "Social Security Receipt PDF",
    },
  });

  const stream = fs.createWriteStream(pdfPath);
  doc.pipe(stream);

  const fonts = applyFonts(doc);

  const pageWidth = doc.page.width;
  const margin = 40;
  const contentWidth = pageWidth - margin * 2;

  const logoSource =
    s(opts.logoUrl) ||
    pickFirst(getValueDeep(data, "clinicSnapshot.logoUrl"), opts.logoPath);

  const logoBuffer = await resolveLogoBuffer(logoSource);

  const headerY = 38;
  const headerH = 158;
  drawBorder(doc, margin, headerY, contentWidth, headerH);

  if (logoBuffer) {
    try {
      doc.image(logoBuffer, margin + 10, 48, {
        fit: [70, 70],
        align: "center",
        valign: "center",
      });
    } catch (_) {}
  }

  const leftStartX = margin + 92;
  const rightPanelX = 360;
  const rightPanelW = 165;
  const clinicTextW = rightPanelX - leftStartX - 14;

  setFont(doc, fonts.bold, 16.5);
  doc.text(clinicName, leftStartX, 50, {
    width: clinicTextW,
    align: "left",
    lineGap: 1.5,
  });

  const clinicLines = [
    clinicBranchName,
    clinicAddress,
    `โทร ${clinicPhone || "-"}`,
    `เลขประจำตัวผู้เสียภาษี ${clinicTaxId || "-"}`,
  ].filter(Boolean);

  setFont(doc, fonts.regular, 8.8);
  doc.text(clinicLines.join("\n"), leftStartX, 78, {
    width: clinicTextW,
    align: "left",
    lineGap: 1.8,
  });

  drawTextBox(doc, {
    x: 410,
    y: 48,
    w: 105,
    h: 30,
    label: "สถานะ",
    value: "ต้นฉบับ",
    fontRegular: fonts.bold,
    fontBold: fonts.bold,
  });

  setFont(doc, fonts.bold, 18.5);
  doc.text("ใบเสร็จรับเงิน", rightPanelX, 86, {
    width: rightPanelW,
    align: "center",
  });

  drawCompactTextBox(doc, {
    x: rightPanelX,
    y: 114,
    w: rightPanelW,
    h: 30,
    label: "วันที่",
    value: formatThaiDate(data.issueDate),
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  drawCompactTextBox(doc, {
    x: rightPanelX,
    y: 148,
    w: rightPanelW,
    h: 30,
    label: "เลขที่",
    value: receiptNo,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  const customerTop = headerY + headerH + 10;
  const servicePeriodValue =
    pickFirst(data.servicePeriodText, data.serviceMonth) || "-";

  const customerBottomY = drawKeyValueRows(
    doc,
    [
      {
        label: "ได้รับเงินจาก",
        value: customerName || "-",
      },
      {
        label: "ที่อยู่",
        value: customerAddress || "-",
      },
      {
        label: "เลขประจำตัวผู้เสียภาษี",
        value: customerTaxId || "-",
      },
      {
        label: "เลขประจำตัวผู้เสียภาษีผู้หัก ณ ที่จ่าย",
        value: withholderTaxId || "-",
      },
      {
        label: "ประจำงวด",
        value: servicePeriodValue,
      },
    ],
    {
      x: margin,
      y: customerTop,
      width: contentWidth,
      rowHeight: 26,
      labelWidth: 175,
      fontRegular: fonts.regular,
      fontBold: fonts.bold,
    }
  );

  const itemsTop = customerBottomY + 10;
  const itemsBottomY = drawItemsTable(doc, data.items || [], {
    x: margin,
    y: itemsTop,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  const amountThaiText = pickFirst(data.amountInThaiText, "-") || "-";
  const amountThaiValueHeight = textHeight(doc, amountThaiText, {
    width: 279,
    fontName: fonts.regular,
    fontSize: 9.5,
    lineGap: 1.5,
  });
  const amountThaiBoxH = Math.max(42, amountThaiValueHeight + 30);
  const amountThaiBoxY = itemsBottomY + 8;

  drawBorder(doc, margin, amountThaiBoxY, 295, amountThaiBoxH);
  setFont(doc, fonts.bold, 9.5);
  doc.text("จำนวนเงิน (ตัวอักษร)", margin + 8, amountThaiBoxY + 6, {
    width: 279,
    lineGap: 1,
  });
  setFont(doc, fonts.regular, 9.5);
  doc.text(amountThaiText, margin + 8, amountThaiBoxY + 21, {
    width: 279,
    align: "left",
    lineGap: 1.5,
  });

  const summaryBottomY = drawSummaryBox(
    doc,
    {
      subtotal: n(data.subtotal, 0),
      withholdingTax: n(data.withholdingTax, 0),
      netAmount: n(data.netAmount, 0),
    },
    {
      x: 340,
      y: amountThaiBoxY,
      width: 215,
      fontRegular: fonts.regular,
      fontBold: fonts.bold,
    }
  );

  let footerStartY = Math.max(amountThaiBoxY + amountThaiBoxH + 8, summaryBottomY + 8);

  if (s(data.note)) {
    const noteHeight = Math.max(
      38,
      textHeight(doc, s(data.note), {
        width: contentWidth - 76,
        fontName: fonts.regular,
        fontSize: 8.9,
        lineGap: 1.3,
      }) + 16
    );

    drawBorder(doc, margin, footerStartY, contentWidth, noteHeight);
    setFont(doc, fonts.bold, 9.2);
    doc.text("หมายเหตุ", margin + 8, footerStartY + 8, {
      width: 56,
      lineGap: 1,
    });
    setFont(doc, fonts.regular, 8.9);
    doc.text(s(data.note), margin + 68, footerStartY + 8, {
      width: contentWidth - 76,
      align: "left",
      lineGap: 1.3,
    });

    footerStartY += noteHeight + 8;
  }

  const paymentAreaHeight = getPaymentAreaHeight(doc, data, {
    width: 260,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });
  const footerPanelHeight = Math.max(100, paymentAreaHeight);

  drawPaymentMethodArea(doc, data, {
    x: margin,
    y: footerStartY,
    width: 260,
    height: footerPanelHeight,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  drawSignatureArea(doc, data, {
    x: 315,
    y: footerStartY,
    width: 240,
    height: footerPanelHeight,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  doc.end();

  await new Promise((resolve, reject) => {
    stream.on("finish", resolve);
    stream.on("error", reject);
  });

  return {
    pdfPath,
    pdfFileName: fileName,
    pdfUrl,
  };
}

module.exports = {
  createPdfFileFromReceipt,
  formatThaiDate,
  formatAmount,
};