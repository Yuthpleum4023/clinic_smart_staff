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
    path.join(base, "fonts", "NotoSansThai-Regular.ttf"),
    path.join(base, "public", "fonts", "NotoSansThai-Regular.ttf"),
  ]);

  const bold = resolveFontPath("PDF_FONT_BOLD_PATH", [
    path.join(base, "assets", "fonts", "NotoSansThai-Bold.ttf"),
    path.join(base, "fonts", "NotoSansThai-Bold.ttf"),
    path.join(base, "public", "fonts", "NotoSansThai-Bold.ttf"),
  ]);

  return { regular, bold };
}

function applyFonts(doc) {
  const fonts = getFontPaths();

  if (fonts.regular) {
    doc.registerFont("TH", fonts.regular);
  }
  if (fonts.bold) {
    doc.registerFont("THB", fonts.bold);
  }

  return {
    regular: fonts.regular ? "TH" : "Helvetica",
    bold: fonts.bold ? "THB" : fonts.regular ? "TH" : "Helvetica-Bold",
    hasThaiFont: !!fonts.regular,
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

  setFont(doc, fontBold, 9);
  doc.text(s(label), x + 6, y + 5, { width: w - 12 });

  setFont(doc, fontRegular, 11);
  doc.text(s(value), x + 6, y + 22, { width: w - 12 });
}

function drawKeyValueRows(
  doc,
  rows,
  options = {}
) {
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
    const h = row.height || rowHeight;
    drawBorder(doc, x, cursorY, width, h);
    drawBorder(doc, x, cursorY, labelWidth, h);

    setFont(doc, fontBold, 10);
    doc.text(s(row.label), x + 6, cursorY + 7, {
      width: labelWidth - 12,
      align: "left",
    });

    setFont(doc, fontRegular, 10);
    doc.text(s(row.value), x + labelWidth + 8, cursorY + 7, {
      width: width - labelWidth - 16,
      align: "left",
    });

    cursorY += h;
  });

  return cursorY;
}

function drawItemsTable(doc, items, options = {}) {
  const {
    x = 40,
    y = 250,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  const colNo = 40;
  const colDesc = 285;
  const colQty = 55;
  const colUnit = 65;
  const colAmount = 70;

  const tableWidth = colNo + colDesc + colQty + colUnit + colAmount;
  const headerHeight = 28;
  const rowHeight = 28;
  const totalRows = Math.max(6, Array.isArray(items) ? items.length : 0);

  drawBorder(doc, x, y, tableWidth, headerHeight);

  const xs = [
    x,
    x + colNo,
    x + colNo + colDesc,
    x + colNo + colDesc + colQty,
    x + colNo + colDesc + colQty + colUnit,
    x + tableWidth,
  ];

  for (let i = 1; i < xs.length - 1; i += 1) {
    doc
      .moveTo(xs[i], y)
      .lineTo(xs[i], y + headerHeight + totalRows * rowHeight)
      .stroke();
  }

  setFont(doc, fontBold, 10);
  doc.text("ลำดับ", x + 4, y + 8, { width: colNo - 8, align: "center" });
  doc.text("รายการ", x + colNo + 4, y + 8, {
    width: colDesc - 8,
    align: "center",
  });
  doc.text("จำนวน", x + colNo + colDesc + 4, y + 8, {
    width: colQty - 8,
    align: "center",
  });
  doc.text("หน่วยละ", x + colNo + colDesc + colQty + 4, y + 8, {
    width: colUnit - 8,
    align: "center",
  });
  doc.text("จำนวนเงิน", x + colNo + colDesc + colQty + colUnit + 4, y + 8, {
    width: colAmount - 8,
    align: "center",
  });

  let cursorY = y + headerHeight;

  for (let i = 0; i < totalRows; i += 1) {
    drawBorder(doc, x, cursorY, tableWidth, rowHeight);

    const item = Array.isArray(items) ? items[i] : null;

    setFont(doc, fontRegular, 10);

    doc.text(item ? String(i + 1) : "", x + 4, cursorY + 8, {
      width: colNo - 8,
      align: "center",
    });

    doc.text(item ? s(item.description) : "", x + colNo + 4, cursorY + 6, {
      width: colDesc - 8,
      align: "left",
      ellipsis: true,
    });

    doc.text(
      item ? formatAmount(n(item.quantity, 0)) : "",
      x + colNo + colDesc + 4,
      cursorY + 8,
      {
        width: colQty - 8,
        align: "right",
      }
    );

    doc.text(
      item ? formatAmount(n(item.unitPrice, 0)) : "",
      x + colNo + colDesc + colQty + 4,
      cursorY + 8,
      {
        width: colUnit - 8,
        align: "right",
      }
    );

    doc.text(
      item ? formatAmount(n(item.amount, 0)) : "",
      x + colNo + colDesc + colQty + colUnit + 4,
      cursorY + 8,
      {
        width: colAmount - 8,
        align: "right",
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
    { label: "ภาษีหัก ณ ที่จ่าย", value: formatAmount(summary.withholdingTax) },
    { label: "จำนวนเงินสุทธิ", value: formatAmount(summary.netAmount), bold: true },
  ];

  let cursorY = y;

  rows.forEach((row) => {
    drawBorder(doc, x, cursorY, width, rowH);
    drawBorder(doc, x, cursorY, labelW, rowH);

    setFont(doc, row.bold ? fontBold : fontRegular, row.bold ? 10.5 : 10);
    doc.text(s(row.label), x + 6, cursorY + 7, {
      width: labelW - 12,
      align: "left",
    });

    doc.text(s(row.value), x + labelW + 6, cursorY + 7, {
      width: width - labelW - 12,
      align: "right",
    });

    cursorY += rowH;
  });

  return cursorY;
}

function drawSignatureArea(doc, data, options = {}) {
  const {
    x = 40,
    y = 675,
    width = 515,
    fontRegular = "Helvetica",
    fontBold = "Helvetica-Bold",
  } = options;

  drawBorder(doc, x, y, width, 85);

  const leftW = 260;
  drawBorder(doc, x, y, leftW, 85);

  setFont(doc, fontBold, 10);
  doc.text("วิธีการชำระเงิน", x + 8, y + 8);

  setFont(doc, fontRegular, 10);
  const methodTextMap = {
    cash: "เงินสด",
    transfer: "โอนเงิน",
    cheque: "เช็ค",
    other: "อื่น ๆ",
  };

  const methodText =
    methodTextMap[s(data.paymentInfo?.method)] ||
    s(data.paymentInfo?.method) ||
    "-";

  doc.text(`วิธีชำระ: ${methodText}`, x + 8, y + 28);
  doc.text(`ธนาคาร: ${s(data.paymentInfo?.bankName) || "-"}`, x + 8, y + 44);
  doc.text(
    `อ้างอิง: ${s(data.paymentInfo?.transferRef || data.paymentInfo?.chequeNo) || "-"}`,
    x + 8,
    y + 60
  );

  const sigX = x + leftW + 16;
  const sigW = width - leftW - 32;

  setFont(doc, fontRegular, 10);
  doc.text("ลงชื่อ ................................................................. ผู้รับเงิน", sigX, y + 20, {
    width: sigW,
    align: "left",
  });
  doc.text(
    `( ${s(data.clinicSnapshot?.clinicName) || "........................................"} )`,
    sigX + 40,
    y + 42,
    { width: sigW - 40, align: "left" }
  );
  doc.text(`วันที่ ${formatThaiDate(data.issueDate)}`, sigX + 70, y + 62, {
    width: sigW - 70,
    align: "left",
  });
}

async function createPdfFileFromReceipt(receipt, opts = {}) {
  const data = typeof receipt?.toObject === "function" ? receipt.toObject() : receipt;
  if (!data) {
    throw new Error("receipt data is required");
  }

  const receiptNo = s(data.receiptNo);
  const clinicId = s(data.clinicId);

  if (!receiptNo) {
    throw new Error("receiptNo is required");
  }
  if (!clinicId) {
    throw new Error("clinicId is required");
  }

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
    s(getValueDeep(data, "clinicSnapshot.logoUrl")) ||
    s(opts.logoPath);

  const logoBuffer = await resolveLogoBuffer(logoSource);

  drawBorder(doc, margin, 38, contentWidth, 135);

  if (logoBuffer) {
    try {
      doc.image(logoBuffer, margin + 10, 48, {
        fit: [70, 70],
        align: "center",
        valign: "center",
      });
    } catch (_) {}
  }

  setFont(doc, fonts.bold, 18);
  doc.text(
    s(getValueDeep(data, "clinicSnapshot.clinicName")) || "ชื่อคลินิก",
    margin + 92,
    48,
    {
      width: 280,
      align: "left",
    }
  );

  setFont(doc, fonts.regular, 10);
  const clinicLines = [
    s(getValueDeep(data, "clinicSnapshot.clinicBranchName")),
    s(getValueDeep(data, "clinicSnapshot.clinicAddress")),
    `โทร ${s(getValueDeep(data, "clinicSnapshot.clinicPhone")) || "-"}`,
    `เลขประจำตัวผู้เสียภาษี ${s(getValueDeep(data, "clinicSnapshot.clinicTaxId")) || "-"}`,
  ].filter(Boolean);

  doc.text(clinicLines.join("\n"), margin + 92, 74, {
    width: 270,
    align: "left",
    lineGap: 2,
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

  setFont(doc, fonts.bold, 20);
  doc.text("ใบเสร็จรับเงิน", 380, 92, { width: 145, align: "center" });

  drawTextBox(doc, {
    x: 380,
    y: 122,
    w: 145,
    h: 45,
    label: "เลขที่",
    value: receiptNo,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  drawTextBox(doc, {
    x: 225,
    y: 122,
    w: 150,
    h: 45,
    label: "วันที่",
    value: formatThaiDate(data.issueDate),
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  const customerTop = 183;

  const servicePeriodValue =
    s(data.servicePeriodText) ||
    s(data.serviceMonth) ||
    "-";

  drawKeyValueRows(
    doc,
    [
      {
        label: "ได้รับเงินจาก",
        value: s(getValueDeep(data, "customerSnapshot.customerName")) || "-",
      },
      {
        label: "ที่อยู่",
        value: s(getValueDeep(data, "customerSnapshot.customerAddress")) || "-",
        height: 40,
      },
      {
        label: "เลขประจำตัวผู้เสียภาษี",
        value: s(getValueDeep(data, "customerSnapshot.customerTaxId")) || "-",
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
      rowHeight: 28,
      labelWidth: 145,
      fontRegular: fonts.regular,
      fontBold: fonts.bold,
    }
  );

  const itemsTop = 300;
  const itemsBottomY = drawItemsTable(doc, data.items || [], {
    x: margin,
    y: itemsTop,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  const amountThaiBoxY = itemsBottomY + 8;
  drawBorder(doc, margin, amountThaiBoxY, 295, 42);
  setFont(doc, fonts.bold, 10);
  doc.text("จำนวนเงิน (ตัวอักษร)", margin + 8, amountThaiBoxY + 6);
  setFont(doc, fonts.regular, 10.5);
  doc.text(s(data.amountInThaiText) || "-", margin + 8, amountThaiBoxY + 21, {
    width: 279,
    align: "left",
  });

  drawSummaryBox(
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

  if (s(data.note)) {
    drawBorder(doc, margin, 612, contentWidth, 48);
    setFont(doc, fonts.bold, 10);
    doc.text("หมายเหตุ", margin + 8, 620);
    setFont(doc, fonts.regular, 10);
    doc.text(s(data.note), margin + 68, 620, {
      width: contentWidth - 76,
      align: "left",
    });
  }

  drawSignatureArea(doc, data, {
    x: margin,
    y: 675,
    width: contentWidth,
    fontRegular: fonts.regular,
    fontBold: fonts.bold,
  });

  setFont(doc, fonts.regular, 8.5);
  doc.text(
    "เอกสารนี้สร้างจากระบบ payroll_service สำหรับใช้งานภายในคลินิก",
    margin,
    785,
    {
      width: contentWidth,
      align: "center",
    }
  );

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