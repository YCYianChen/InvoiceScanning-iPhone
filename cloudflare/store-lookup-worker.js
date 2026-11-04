// Cloudflare Worker：以統一編號查詢經濟部商工登記資料（公司 → 商業登記）
// 用法：GET https://<你的 worker>.workers.dev/?id=12345678
// 回傳：{ "name": "店家名稱", "address": "登記地址" }
// 只允許你的網頁版呼叫，並只轉發這兩個查詢，不能拿來連其他網站。

const ALLOWED_ORIGINS = ["https://ycyianchen.github.io"];

const APIS = [
  { id: "5F64D864-61CB-4D0D-8AD9-492047CC1EA6", field: "Business_Accounting_NO", name: "Company_Name", addr: "Company_Location" },
  { id: "7E6AFA72-AD6A-46D3-8681-ED77951D912D", field: "President_No", name: "Business_Name", addr: "Business_Address" },
];

export default {
  async fetch(request) {
    const origin = request.headers.get("Origin") || "";
    const allowed = ALLOWED_ORIGINS.includes(origin);
    const cors = {
      "Access-Control-Allow-Origin": allowed ? origin : ALLOWED_ORIGINS[0],
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Vary": "Origin",
    };
    const json = (body, status = 200) =>
      new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });

    if (request.method === "OPTIONS") return new Response(null, { headers: cors });
    if (origin && !allowed) return json({ error: "forbidden" }, 403);
    if (request.method !== "GET") return json({ error: "method not allowed" }, 405);

    const id = new URL(request.url).searchParams.get("id") || "";
    if (!/^\d{8}$/.test(id)) return json({ error: "統一編號必須是 8 碼數字" }, 400);

    for (const api of APIS) {
      const url = `https://data.gcis.nat.gov.tw/od/data/api/${api.id}` +
        `?$format=json&$filter=${encodeURIComponent(`${api.field} eq ${id}`)}&$skip=0&$top=1`;
      try {
        // 同一個統編一天內只查一次經濟部
        const r = await fetch(url, { cf: { cacheTtl: 86400, cacheEverything: true } });
        const text = await r.text();
        if (!text.trim()) continue;
        const arr = JSON.parse(text);
        const row = Array.isArray(arr) ? arr[0] : null;
        if (row && (row[api.name] || row[api.addr])) {
          return json({ name: row[api.name] || "", address: row[api.addr] || "" });
        }
      } catch (e) {
        // 換下一個資料集
      }
    }
    return json({ name: "", address: "" }, 404);
  },
};
