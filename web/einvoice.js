// 台灣電子發票證明聯 QR Code 解析
// 左側 QR 前 77 碼：發票號碼(10) 民國日期yyyMMdd(7) 隨機碼(4) 銷售額hex(8) 總計額hex(8)
//                  買方統編(8) 賣方統編(8) 加密驗證(24)
// 之後以 ":" 分隔：自行使用區 : 本QR品項數 : 品項總數 : 編碼(0=Big5,1=UTF-8,2=Base64) : 品名:數量:單價:...
// 右側 QR 以 "**" 開頭，接續品項。
(function (root) {
  function isLeft(s) {
    return typeof s === "string" && s.length >= 77 && /^[A-Z]{2}\d{19}/.test(s);
  }
  function isRight(s) {
    return typeof s === "string" && s.startsWith("**");
  }

  function rocDate(s) {
    if (!/^\d{7}$/.test(s)) return null;
    const y = +s.slice(0, 3) + 1911, m = +s.slice(3, 5), d = +s.slice(5, 7);
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  }

  function b64(s) {
    if (!s) return s;
    try {
      const bin = atob(s);
      const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
      return new TextDecoder("utf-8").decode(bytes);
    } catch (e) {
      return s;
    }
  }

  function itemsFrom(fields) {
    const out = [];
    for (let i = 0; i + 2 < fields.length; i += 3) {
      const name = fields[i], q = Number(fields[i + 1]), p = Number(fields[i + 2]);
      if (name && fields[i + 1] !== "" && fields[i + 2] !== "" && isFinite(q) && isFinite(p)) {
        out.push({ name, qty: q, price: p });
      }
    }
    return out;
  }

  function parseItems(left, right) {
    // 品項可能被切在左右兩個 QR 之間：先直接串接，欄位數不是 3 的倍數再改用 ":" 串接
    const candidates = right ? [left + right, left + ":" + right] : [left];
    let best = [];
    for (const joined of candidates) {
      const f = joined.split(":").map((x) => x.trim());
      while (f.length && f[f.length - 1] === "") f.pop();
      const items = itemsFrom(f);
      if (f.length % 3 === 0 && items.length) return items;
      if (items.length > best.length) best = items;
    }
    return best;
  }

  /** 回傳編碼參數（"0"/"1"/"2"），解析前用來判斷是否要改用 Big5 解碼 */
  function encodingOf(left) {
    if (!isLeft(left)) return null;
    const parts = left.slice(78).split(":");
    return parts.length >= 4 ? parts[3] : null;
  }

  function parse(left, right) {
    if (!isLeft(left)) return null;
    const date = rocDate(left.slice(10, 17));
    if (!date) return null;
    const res = {
      number: left.slice(0, 10),
      date,
      randomCode: left.slice(17, 21),
      sales: parseInt(left.slice(21, 29), 16) || 0,
      total: parseInt(left.slice(29, 37), 16) || 0,
      buyerTaxID: left.slice(37, 45),
      sellerTaxID: left.slice(45, 53),
      items: [],
      declaredCount: 0,
    };
    let tail = left.slice(77);
    if (tail.startsWith(":")) tail = tail.slice(1);
    const parts = tail.split(":");
    if (parts.length >= 4) {
      res.declaredCount = parseInt(parts[2], 10) || 0;
      const enc = parts[3];
      let itemsPart = parts.slice(4).join(":");
      let rightPart = isRight(right) ? right.slice(2) : "";
      if (enc === "2") {
        itemsPart = b64(itemsPart);
        rightPart = b64(rightPart);
      }
      res.items = parseItems(itemsPart, rightPart);
    }
    return res;
  }

  root.EInvoice = { isLeft, isRight, parse, encodingOf, rocDate };
  if (typeof module !== "undefined") module.exports = root.EInvoice;
})(typeof window !== "undefined" ? window : globalThis);
