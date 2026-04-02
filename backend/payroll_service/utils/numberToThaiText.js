function roundSatang(amount) {
  const n = Number(amount || 0);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.round(n * 100) / 100;
}

const THAI_NUM_TEXT = [
  "ศูนย์",
  "หนึ่ง",
  "สอง",
  "สาม",
  "สี่",
  "ห้า",
  "หก",
  "เจ็ด",
  "แปด",
  "เก้า",
];

const THAI_POS_TEXT = ["", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน", "ล้าน"];

function convertBelowMillion(num) {
  const n = Math.floor(Number(num || 0));
  if (!n) return "";

  const digits = String(n).split("").map(Number);
  const len = digits.length;
  let out = "";

  for (let i = 0; i < len; i += 1) {
    const d = digits[i];
    const pos = len - i - 1;

    if (d === 0) continue;

    if (pos === 0) {
      if (d === 1 && len > 1) {
        out += "เอ็ด";
      } else {
        out += THAI_NUM_TEXT[d];
      }
      continue;
    }

    if (pos === 1) {
      if (d === 1) {
        out += "สิบ";
      } else if (d === 2) {
        out += "ยี่สิบ";
      } else {
        out += `${THAI_NUM_TEXT[d]}สิบ`;
      }
      continue;
    }

    out += `${THAI_NUM_TEXT[d]}${THAI_POS_TEXT[pos]}`;
  }

  return out;
}

function convertIntegerPart(num) {
  let n = Math.floor(Number(num || 0));
  if (!n) return "ศูนย์";

  let result = "";
  let millionIndex = 0;

  while (n > 0) {
    const chunk = n % 1000000;
    if (chunk > 0) {
      const text = convertBelowMillion(chunk);
      const millionText = millionIndex > 0 ? "ล้าน".repeat(millionIndex) : "";
      result = `${text}${millionText}${result}`;
    }
    n = Math.floor(n / 1000000);
    millionIndex += 1;
  }

  return result || "ศูนย์";
}

function numberToThaiText(amount) {
  const safeAmount = roundSatang(amount);

  const integerPart = Math.floor(safeAmount);
  const satang = Math.round((safeAmount - integerPart) * 100);

  const bahtText = `${convertIntegerPart(integerPart)}บาท`;

  if (satang === 0) {
    return `${bahtText}ถ้วน`;
  }

  return `${bahtText}${convertIntegerPart(satang)}สตางค์`;
}

module.exports = {
  numberToThaiText,
};