(() => {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const LEGACY_KEY = "invoices.v1"; // 舊版存在手機的資料，登入後會自動上傳

  const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  const today = () => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  };
  const money = (n) => "$" + Math.round(Number(n) || 0).toLocaleString("zh-TW");
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const weekday = ["日", "一", "二", "三", "四", "五", "六"];

  let toastTimer;
  function toast(msg) {
    const t = $("toast"); t.textContent = msg; t.hidden = false;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => (t.hidden = true), 2800);
  }

  // ---------- 雲端資料（Firebase） ----------
  // 資料路徑：users/{uid}/invoices/{發票號碼或隨機 id}
  const cfg = window.FIREBASE_CONFIG;
  const configured = !!(cfg && cfg.apiKey && !cfg.apiKey.startsWith("請填"));
  let auth = null, db = null, user = null, unsub = null, migrated = false;
  let invoices = [];
  let syncText = "";

  function sanitize(inv) {
    return {
      number: String(inv.number || "").slice(0, 20),
      date: String(inv.date || today()),
      total: Number(inv.total) || 0,
      sellerTaxID: String(inv.sellerTaxID || "").slice(0, 20),
      storeName: String(inv.storeName || "").slice(0, 200),
      storeAddress: String(inv.storeAddress || "").slice(0, 300),
      note: String(inv.note || "").slice(0, 2000),
      items: (inv.items || []).slice(0, 300).map((x) => ({
        name: String(x.name || ""), qty: Number(x.qty) || 0, price: Number(x.price) || 0,
      })),
      createdAt: Number(inv.createdAt) || Date.now(),
      updatedAt: Date.now(),
    };
  }
  const docIdFor = (number) => (/^[A-Z]{2}\d{8}$/.test(number) ? number : uid());
  const col = () => FB.collection(db, "users", user.uid, "invoices");

  function writeInvoice(id, inv) {
    // 不等伺服器回應：離線時會先存在手機，連上網路後自動上傳
    FB.setDoc(FB.doc(col(), id), sanitize(inv)).catch((e) => toast("同步失敗（" + e.code + "）"));
  }
  function removeInvoice(id) {
    FB.deleteDoc(FB.doc(col(), id)).catch((e) => toast("刪除失敗（" + e.code + "）"));
  }
  async function writeMany(list) {
    let n = 0, batch = FB.writeBatch(db), inBatch = 0;
    for (const inv of list) {
      const id = typeof inv.id === "string" && inv.id && !inv.id.includes("/") ? inv.id : docIdFor(String(inv.number || ""));
      batch.set(FB.doc(col(), id), sanitize(inv));
      n++; inBatch++;
      if (inBatch === 400) { await batch.commit(); batch = FB.writeBatch(db); inBatch = 0; }
    }
    if (inBatch) await batch.commit();
    return n;
  }

  if (configured) {
    const app = FB.initializeApp(cfg);
    auth = FB.initializeAuth(app, { persistence: [FB.indexedDBLocalPersistence, FB.browserLocalPersistence] });
    try {
      db = FB.initializeFirestore(app, { localCache: FB.persistentLocalCache({ tabManager: FB.persistentMultipleTabManager() }) });
    } catch (e) {
      db = FB.initializeFirestore(app, {});
    }
    FB.onAuthStateChanged(auth, onUser);
  } else {
    $("setupMsg").hidden = false;
    $("authForm").hidden = true;
    $("authSheet").hidden = false;
  }

  function onUser(u) {
    user = u;
    if (unsub) { unsub(); unsub = null; }
    invoices = []; migrated = false; render();
    if (!u) { $("authSheet").hidden = false; return; }
    $("authSheet").hidden = true;
    $("accountEmail").textContent = u.email || "";
    unsub = FB.onSnapshot(col(), { includeMetadataChanges: true }, (snap) => {
      invoices = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
      syncText = snap.metadata.hasPendingWrites ? "有資料等待上傳…"
        : snap.metadata.fromCache ? "離線中，顯示手機上的資料" : "已同步";
      $("syncState").textContent = syncText;
      render();
      if (!migrated && !snap.metadata.fromCache) { migrated = true; migrateLegacy(); }
    }, (err) => toast("讀取資料失敗（" + err.code + "）"));
  }

  async function migrateLegacy() {
    let old = [];
    try { old = JSON.parse(localStorage.getItem(LEGACY_KEY) || "[]"); } catch (e) { return; }
    if (!Array.isArray(old) || !old.length) return;
    const fresh = old.filter((o) => o && o.date && !(o.number && invoices.some((i) => i.number === o.number)));
    try {
      const n = fresh.length ? await writeMany(fresh) : 0;
      localStorage.setItem(LEGACY_KEY + ".uploaded", localStorage.getItem(LEGACY_KEY));
      localStorage.removeItem(LEGACY_KEY);
      if (n) toast(`已把這支手機上的 ${n} 張發票上傳到帳號`);
    } catch (e) { /* 下次登入再試 */ }
  }

  // ---------- 登入 ----------
  let signUpMode = false;
  const authErrors = {
    "auth/invalid-credential": "Email 或密碼錯誤",
    "auth/wrong-password": "Email 或密碼錯誤",
    "auth/user-not-found": "Email 或密碼錯誤",
    "auth/invalid-email": "Email 格式不正確",
    "auth/email-already-in-use": "這個 Email 已經註冊過，請直接登入",
    "auth/weak-password": "密碼至少要 6 個字元",
    "auth/missing-password": "請輸入密碼",
    "auth/too-many-requests": "嘗試次數太多，請稍後再試",
    "auth/network-request-failed": "網路連線失敗，請檢查網路",
  };
  const authMsg = (e) => authErrors[e.code] || "發生錯誤（" + (e.code || e.message) + "）";

  function setAuthMode(up) {
    signUpMode = up;
    $("authSubmit").textContent = up ? "註冊並登入" : "登入";
    $("authToggle").textContent = up ? "已經有帳號？登入" : "還沒有帳號？註冊";
    $("authPassword").autocomplete = up ? "new-password" : "current-password";
    $("authError").hidden = true;
  }
  $("authToggle").onclick = () => setAuthMode(!signUpMode);
  $("authForm").onsubmit = async (e) => {
    e.preventDefault();
    const email = $("authEmail").value.trim(), pw = $("authPassword").value;
    const btn = $("authSubmit"); btn.disabled = true; $("authError").hidden = true;
    try {
      if (signUpMode) {
        const cred = await FB.createUserWithEmailAndPassword(auth, email, pw);
        FB.sendEmailVerification(cred.user).catch(() => {});
      } else {
        await FB.signInWithEmailAndPassword(auth, email, pw);
      }
      $("authPassword").value = "";
    } catch (err) {
      $("authError").textContent = authMsg(err); $("authError").hidden = false;
    } finally { btn.disabled = false; }
  };
  $("authForgot").onclick = async () => {
    const email = $("authEmail").value.trim();
    if (!email) { $("authError").textContent = "請先在上方輸入 Email"; $("authError").hidden = false; return; }
    try { await FB.sendPasswordResetEmail(auth, email); toast("已寄出重設密碼信，請收信"); }
    catch (err) { $("authError").textContent = authMsg(err); $("authError").hidden = false; }
  };

  // ---------- 清單 ----------
  let viewMonth = today().slice(0, 7);
  function shiftMonth(delta) {
    let [y, m] = viewMonth.split("-").map(Number);
    m += delta; if (m < 1) { m = 12; y--; } if (m > 12) { m = 1; y++; }
    viewMonth = `${y}-${String(m).padStart(2, "0")}`; render();
  }
  $("prevMonth").onclick = () => shiftMonth(-1);
  $("nextMonth").onclick = () => shiftMonth(1);
  $("search").oninput = render;

  function render() {
    const q = $("search").value.trim().toLowerCase();
    const [y, m] = viewMonth.split("-");
    $("monthLabel").textContent = `${y} 年 ${+m} 月`;

    const inMonth = invoices.filter((i) => String(i.date).startsWith(viewMonth));
    $("monthSum").textContent = money(inMonth.reduce((s, i) => s + (Number(i.total) || 0), 0));
    $("monthCount").textContent = `共 ${inMonth.length} 張`;

    // 搜尋時跨月份搜尋全部
    const shown = (q ? invoices : inMonth).filter((i) => !q || [
      i.storeName, i.note, i.number, i.storeAddress, ...(i.items || []).map((x) => x.name),
    ].some((s) => String(s || "").toLowerCase().includes(q)));

    const byDay = {};
    for (const inv of shown) (byDay[inv.date] ||= []).push(inv);
    const days = Object.keys(byDay).sort().reverse();

    const list = $("list");
    if (!days.length) {
      list.innerHTML = q
        ? `<div class="empty"><p>找不到「${esc(q)}」</p></div>`
        : `<div class="empty">
             <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M6 3h12v18l-2-1.5-2 1.5-2-1.5-2 1.5-2-1.5L6 21z"/><path d="M9 8h6M9 12h6M9 16h3"/></svg>
             <p>這個月還沒有發票<br>按下方「掃描發票」開始記錄</p>
             <span class="tag">支援電子發票證明聯上的 QR Code</span>
           </div>`;
      return;
    }
    list.innerHTML = days.map((d) => {
      const arr = byDay[d].sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
      const dt = new Date(d + "T00:00:00");
      const sub = arr.reduce((s, i) => s + (Number(i.total) || 0), 0);
      return `<section class="day">
        <div class="day-head"><span>${dt.getMonth() + 1} 月 ${dt.getDate()} 日（${weekday[dt.getDay()]}）${q ? "・" + dt.getFullYear() : ""}</span><span>小計 <b>${money(sub)}</b></span></div>
        <div class="card-list">${arr.map((i) => `
          <button class="inv" data-id="${esc(i.id)}">
            <span class="store">${esc(i.storeName || (i.sellerTaxID ? "統編 " + i.sellerTaxID : "未命名店家"))}</span>
            <span class="amt">${money(i.total)}</span>
            ${i.items && i.items.length ? `<span class="items">${esc(i.items.map((x) => x.name).join("、"))}</span>` : ""}
            ${i.note ? `<span class="note">${esc(i.note)}</span>` : ""}
          </button>`).join("")}
        </div></section>`;
    }).join("");
  }
  $("list").onclick = (e) => {
    const b = e.target.closest(".inv"); if (!b) return;
    const inv = invoices.find((i) => i.id === b.dataset.id);
    if (inv) openForm(inv, false);
  };

  // ---------- 表單 ----------
  let editing = null; // 正在編輯的現有發票（null = 新增）
  let draftItems = [];
  function openForm(data, isNew, fromScan) {
    editing = isNew ? null : data;
    $("formTitle").textContent = isNew ? (fromScan ? "確認發票" : "手動新增") : "發票內容";
    $("fNumber").value = data.number || "";
    $("fDate").value = data.date || today();
    $("fTotal").value = data.total ?? "";
    $("fSeller").value = data.sellerTaxID || "";
    $("fStore").value = data.storeName || "";
    $("fAddr").value = data.storeAddress || "";
    $("fNote").value = data.note || "";
    draftItems = (data.items || []).map((x) => ({ ...x }));
    renderItems(); updateMap();
    $("deleteArea").hidden = isNew; $("deleteConfirm").hidden = true; $("btnDelete").hidden = false;
    $("formSheet").hidden = false; $("formSheet").scrollTop = 0;
    renderStoreChips(isNew ? data.sellerTaxID : "");
    if (fromScan && !data.storeName && data.sellerTaxID) {
      const combos = storeCombos(data.sellerTaxID);
      if (combos.length === 1) {
        // 這個統編以前只對應過一組店名，直接沿用（仍可修改）
        $("fStore").value = combos[0].name;
        $("fAddr").value = combos[0].addr;
        updateMap();
        $("storeHint").textContent = "已沿用你上次為這個統編填的店名，不對的話可以直接修改";
        $("storeHint").hidden = false;
      } else if (combos.length === 0) {
        lookupStore(true);
      }
      // 多組時不自動帶入，讓你從下方選項挑
    }
  }

  /** 你以前為同一個統編填過的店名＋地址（去除重複，最近的在前） */
  function storeCombos(taxID) {
    if (!taxID) return [];
    const seen = new Map();
    invoices
      .filter((i) => i.sellerTaxID === taxID && i.storeName && (!editing || i.id !== editing.id))
      .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
      .forEach((i) => {
        const key = i.storeName + "|" + (i.storeAddress || "");
        if (!seen.has(key)) seen.set(key, { name: i.storeName, addr: i.storeAddress || "" });
      });
    return [...seen.values()].slice(0, 6);
  }
  function renderStoreChips(taxID) {
    const combos = storeCombos(taxID);
    $("storeHint").hidden = true;
    $("storeChips").hidden = combos.length < 2;
    $("storeChips").innerHTML = combos.length < 2 ? "" :
      `<span class="chips-label">這個統編以前記錄過：</span>` +
      combos.map((c, i) => `<button type="button" class="chip" data-i="${i}">${esc(c.name)}${c.addr ? `<small>${esc(c.addr)}</small>` : ""}</button>`).join("");
    $("storeChips").onclick = (e) => {
      const b = e.target.closest(".chip"); if (!b) return;
      const c = combos[+b.dataset.i];
      $("fStore").value = c.name; $("fAddr").value = c.addr; updateMap();
    };
  }
  function closeForm() { $("formSheet").hidden = true; editing = null; }

  function renderItems() {
    const box = $("itemsBox");
    if (!draftItems.length) {
      box.innerHTML = `<div class="field"><span style="color:var(--muted);font-size:14px">沒有品項資料，可按「新增品項」手動加入</span></div>`;
    } else {
      box.innerHTML = draftItems.map((it, i) => `
        <div class="item-row" data-i="${i}">
          <input data-k="name" value="${esc(it.name)}" placeholder="品名" aria-label="品名">
          <input data-k="qty" class="n" type="number" inputmode="decimal" value="${esc(it.qty)}" aria-label="數量">
          <input data-k="price" class="n" type="number" inputmode="decimal" value="${esc(it.price)}" aria-label="單價">
          <button type="button" class="x" aria-label="移除品項">×</button>
        </div>`).join("");
    }
    updateItemsSum();
  }
  function updateItemsSum() {
    const s = draftItems.reduce((a, x) => a + (Number(x.qty) || 0) * (Number(x.price) || 0), 0);
    $("itemsSum").textContent = draftItems.length ? `品項合計 ${money(s)}` : "";
  }
  $("itemsBox").oninput = (e) => {
    const row = e.target.closest(".item-row"); if (!row) return;
    const it = draftItems[+row.dataset.i], k = e.target.dataset.k;
    it[k] = k === "name" ? e.target.value : Number(e.target.value);
    updateItemsSum();
  };
  $("itemsBox").onclick = (e) => {
    if (!e.target.classList.contains("x")) return;
    draftItems.splice(+e.target.closest(".item-row").dataset.i, 1); renderItems();
  };
  $("btnAddItem").onclick = () => {
    draftItems.push({ name: "", qty: 1, price: 0 }); renderItems();
    const rows = $("itemsBox").querySelectorAll(".item-row");
    rows[rows.length - 1]?.querySelector("input").focus();
  };

  function updateMap() {
    const a = $("fAddr").value.trim() || $("fStore").value.trim();
    $("btnMap").hidden = !a;
    if (a) $("btnMap").href = "https://maps.apple.com/?q=" + encodeURIComponent(a);
  }
  $("fAddr").oninput = updateMap; $("fStore").oninput = updateMap;

  async function lookupStore(silent) {
    const id = $("fSeller").value.trim();
    if (!/^\d{8}$/.test(id) || id === "00000000") { if (!silent) toast("請先輸入 8 碼統一編號"); return; }
    const btn = $("btnLookup"); btn.disabled = true; btn.textContent = "查詢中…";
    const apis = [
      ["5F64D864-61CB-4D0D-8AD9-492047CC1EA6", `Business_Accounting_NO eq ${id}`, "Company_Name", "Company_Location"],
      ["7E6AFA72-AD6A-46D3-8681-ED77951D912D", `President_No eq ${id}`, "Business_Name", "Business_Address"],
    ];
    let found = null, failed = false;
    if (window.STORE_PROXY) {
      try {
        const r = await fetch(`${window.STORE_PROXY.replace(/\/$/, "")}/?id=${id}`, { signal: AbortSignal.timeout ? AbortSignal.timeout(10000) : undefined });
        if (r.status === 404) { btn.disabled = false; btn.textContent = "依統編查詢店家"; if (!silent) toast("查無這個統編的登記資料"); return; }
        const d = await r.json();
        if (d.name || d.address) found = { name: d.name || "", addr: d.address || "" };
        else if (r.status === 502) { btn.disabled = false; btn.textContent = "依統編查詢店家"; if (!silent) toast("查詢服務暫時連不上，請稍後再試或手動輸入"); return; }
      } catch (e) { failed = true; }
    }
    for (const [api, filter, nk, ak] of found ? [] : apis) {
      try {
        const url = `https://data.gcis.nat.gov.tw/od/data/api/${api}?$format=json&$filter=${encodeURIComponent(filter)}&$skip=0&$top=1`;
        const r = await fetch(url, { signal: AbortSignal.timeout ? AbortSignal.timeout(8000) : undefined });
        const text = await r.text();
        if (!text.trim()) continue;
        const arr = JSON.parse(text);
        if (Array.isArray(arr) && arr[0] && (arr[0][nk] || arr[0][ak])) { found = { name: arr[0][nk] || "", addr: arr[0][ak] || "" }; break; }
      } catch (e) { failed = true; }
    }
    if (!found) {
      // 備用來源：g0v 公司資料 API（經濟部網站不允許網頁直接讀取時使用）
      try {
        const r = await fetch(`https://company.g0v.ronny.tw/api/show/${id}`, { signal: AbortSignal.timeout ? AbortSignal.timeout(8000) : undefined });
        const d = (await r.json()).data || {};
        const name = d["公司名稱"] || d["商業名稱"] || d["名稱"] || "";
        const addr = d["公司所在地"] || d["地址"] || d["商業所在地"] || "";
        if (name || addr) { found = { name: typeof name === "string" ? name : "", addr: typeof addr === "string" ? addr : "" }; failed = false; }
      } catch (e) { failed = true; }
    }
    btn.disabled = false; btn.textContent = "依統編查詢店家";
    if (found) {
      if (!$("fStore").value.trim()) $("fStore").value = found.name;
      if (!$("fAddr").value.trim()) $("fAddr").value = found.addr;
      updateMap();
      if (!silent) toast("已帶入登記資料");
    } else if (!silent) {
      toast(failed ? "查詢服務連不上，請手動輸入" : "查無這個統編的登記資料");
    }
  }
  $("btnLookup").onclick = () => lookupStore(false);

  $("formCancel").onclick = closeForm;
  $("form").onsubmit = (e) => { e.preventDefault(); save(); };
  $("formSave").onclick = save;
  function save() {
    if (!user) { toast("請先登入"); return; }
    const number = $("fNumber").value.trim().toUpperCase();
    const date = $("fDate").value;
    if (!date) { toast("請填消費日期"); return; }
    if (number && invoices.some((i) => i.number === number && (!editing || i.id !== editing.id))) {
      toast(`發票 ${number} 已經記錄過了`); return;
    }
    const data = {
      number, date,
      total: Number($("fTotal").value) || 0,
      sellerTaxID: $("fSeller").value.trim(),
      storeName: $("fStore").value.trim(),
      storeAddress: $("fAddr").value.trim(),
      note: $("fNote").value.trim(),
      items: draftItems.filter((x) => String(x.name).trim()),
    };
    const msg = editing ? "已更新" : "已儲存";
    if (editing) writeInvoice(editing.id, { ...editing, ...data });
    else writeInvoice(docIdFor(number), { ...data, createdAt: Date.now() });
    viewMonth = date.slice(0, 7); $("search").value = "";
    closeForm(); render(); toast(msg);
  }
  $("btnDelete").onclick = () => { $("deleteConfirm").hidden = false; $("btnDelete").hidden = true; };
  $("btnDeleteNo").onclick = () => { $("deleteConfirm").hidden = true; $("btnDelete").hidden = false; };
  $("btnDeleteYes").onclick = () => { removeInvoice(editing.id); closeForm(); toast("已刪除"); };
  $("btnManual").onclick = () => openForm({ date: today() }, true, false);

  // ---------- 掃描 ----------
  let stream = null, timer = null, codeL = null, codeR = null, bytesL = null, bytesR = null, finished = false;
  const canvas = $("canvas"), ctx = canvas.getContext("2d", { willReadFrequently: true });
  let scanSource = null;

  // 編碼參數為 0（Big5）時改用 Big5 重新解碼
  function big5(bytes) {
    try { return new TextDecoder("big5").decode(new Uint8Array(bytes)); } catch (e) { return null; }
  }
  function currentParse() {
    if (!codeL) return null;
    let L = codeL, R = codeR;
    if (EInvoice.encodingOf(codeL) === "0") {
      L = (bytesL && big5(bytesL)) || L;
      R = R && ((bytesR && big5(bytesR)) || R);
    }
    return EInvoice.parse(L, R);
  }

  function accept(code) {
    const s = code && code.data; if (!s) return;
    if (EInvoice.isLeft(s)) {
      if (s !== codeL) { if (codeL) { codeR = null; bytesR = null; } codeL = s; bytesL = code.binaryData; }
    } else if (EInvoice.isRight(s)) {
      codeR = s; bytesR = code.binaryData;
    }
  }

  function updateScanUI() {
    $("markL").classList.toggle("got", !!codeL);
    $("markR").classList.toggle("got", !!codeR);
    const p = currentParse();
    $("scanUse").hidden = !p; $("scanRes").hidden = !p;
    if (p) {
      $("scanRes").textContent = `${p.number}　${money(p.total)}　品項 ${p.items.length}/${p.declaredCount}`;
      $("scanTip").textContent = codeR ? "已讀到兩個 QR Code" : "已讀到左側，請把右側 QR Code 也放進框內";
      if ((p.declaredCount > 0 && p.items.length >= p.declaredCount) || (codeR && p.declaredCount === 0)) finish();
    }
  }

  function scanRegion(sx, sy, sw, sh) {
    const maxW = 900, scale = Math.min(1, maxW / sw);
    const w = Math.round(sw * scale), h = Math.round(sh * scale);
    canvas.width = w; canvas.height = h;
    ctx.drawImage(scanSource, sx, sy, sw, sh, 0, 0, w, h);
    const img = ctx.getImageData(0, 0, w, h);
    return jsQR(img.data, w, h, { inversionAttempts: "dontInvert" });
  }
  function scanFrame(src, sw, sh) {
    scanSource = src;
    // 整張、左半、右半各試一次，才能抓到並排的兩個 QR
    for (const [x, w] of [[0, sw], [0, sw * 0.55], [sw * 0.45, sw * 0.55]]) {
      const c = scanRegion(x, 0, w, sh);
      if (c) accept(c);
    }
    updateScanUI();
  }

  async function openScanner() {
    if (!user) { toast("請先登入"); return; }
    codeL = codeR = bytesL = bytesR = null; finished = false;
    $("scanErr").hidden = true; $("scanTip").textContent = "把發票上的兩個 QR Code 放進框內，保持穩定";
    $("scanSheet").hidden = false; updateScanUI();
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment", width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false,
      });
      const v = $("video"); v.srcObject = stream; await v.play();
      const tick = () => {
        if (!stream || finished) return;
        if (v.readyState >= 2 && v.videoWidth) {
          // 只掃畫面中間（掃描框附近）的區域，速度較快
          const vw = v.videoWidth, vh = v.videoHeight;
          const cw = vw * 0.92, ch = Math.min(vh, cw * 0.7);
          const sx = (vw - cw) / 2, sy = Math.max(0, vh * 0.42 - ch / 2);
          scanSource = v;
          for (const [x, w] of [[sx, cw], [sx, cw * 0.55], [sx + cw * 0.45, cw * 0.55]]) {
            const c = scanRegion(x, sy, w, Math.min(ch, vh - sy));
            if (c) accept(c);
          }
          updateScanUI();
        }
        timer = setTimeout(tick, 120);
      };
      tick();
    } catch (e) {
      $("scanErr").hidden = false;
      $("scanErr").textContent = location.protocol !== "https:" && location.hostname !== "localhost"
        ? "相機只能在 https 網址下使用。請用部署好的網址開啟。"
        : "無法開啟相機。請到「設定 → Safari → 相機」改成「允許」，或改用下方「用拍照辨識」。";
    }
  }
  function stopScanner() {
    clearTimeout(timer); timer = null;
    if (stream) stream.getTracks().forEach((t) => t.stop());
    stream = null; $("video").srcObject = null; $("scanSheet").hidden = true;
  }
  function finish() {
    if (finished) return;
    const p = currentParse(); if (!p) return;
    finished = true;
    if (navigator.vibrate) navigator.vibrate(30);
    stopScanner();
    const dup = invoices.find((i) => i.number === p.number);
    if (dup) { toast(`發票 ${p.number} 已經記錄過了`); openForm(dup, false); return; }
    openForm({ number: p.number, date: p.date, total: p.total, sellerTaxID: p.sellerTaxID, items: p.items }, true, true);
  }
  $("btnScan").onclick = openScanner;
  $("scanCancel").onclick = stopScanner;
  $("scanUse").onclick = finish;
  $("photoInput").onchange = async (e) => {
    const f = e.target.files[0]; e.target.value = ""; if (!f) return;
    try {
      const bmp = await createImageBitmap(f);
      scanFrame(bmp, bmp.width, bmp.height);
      if (!codeL) toast("照片裡找不到發票 QR Code，請靠近一點、避免反光再拍一次");
      else if (!finished && !codeR) toast("只讀到左側 QR Code，可直接按「使用目前結果」");
    } catch (err) { toast("無法讀取照片"); }
  };

  // ---------- 設定、帳號、備份 ----------
  $("btnSettings").onclick = () => {
    $("settingsSheet").hidden = false;
    $("storageInfo").textContent = `帳號中共 ${invoices.length} 張發票。`;
    $("accountConfirm").hidden = true; $("btnDeleteAccount").hidden = false;
  };
  $("settingsClose").onclick = () => ($("settingsSheet").hidden = true);
  $("btnSignOut").onclick = async () => {
    await FB.signOut(auth); $("settingsSheet").hidden = true; toast("已登出");
  };
  $("btnDeleteAccount").onclick = () => { $("accountConfirm").hidden = false; $("btnDeleteAccount").hidden = true; };
  $("btnDeleteAccountNo").onclick = () => { $("accountConfirm").hidden = true; $("btnDeleteAccount").hidden = false; };
  $("btnDeleteAccountYes").onclick = async () => {
    try {
      const snap = await FB.getDocs(col());
      let batch = FB.writeBatch(db), n = 0;
      for (const d of snap.docs) {
        batch.delete(d.ref);
        if (++n % 400 === 0) { await batch.commit(); batch = FB.writeBatch(db); }
      }
      await batch.commit();
      await FB.deleteUser(auth.currentUser);
      $("settingsSheet").hidden = true; toast("帳號與所有發票已刪除");
    } catch (e) {
      toast(e.code === "auth/requires-recent-login" ? "為了安全，請登出後重新登入，再刪除帳號" : "刪除失敗（" + e.code + "）");
    }
  };

  async function shareOrDownload(filename, text, type) {
    const file = new File([text], filename, { type });
    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      try { await navigator.share({ files: [file], title: filename }); return; }
      catch (e) { if (e.name === "AbortError") return; }
    }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(file); a.download = filename; document.body.appendChild(a); a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }
  const stamp = () => today().replace(/-/g, "");
  $("btnExportJson").onclick = () =>
    shareOrDownload(`發票備份-${stamp()}.json`, JSON.stringify({ app: "invoice-scanner", version: 2, invoices }, null, 2), "application/json");
  $("btnExportCsv").onclick = () => {
    const q = (s) => `"${String(s ?? "").replace(/"/g, '""')}"`;
    const rows = [["日期", "發票號碼", "金額", "店家", "地址", "統編", "品項", "備註"].map(q).join(",")];
    for (const i of [...invoices].sort((a, b) => String(a.date).localeCompare(String(b.date)))) {
      rows.push([i.date, i.number, i.total, i.storeName, i.storeAddress, i.sellerTaxID,
        (i.items || []).map((x) => `${x.name}×${x.qty}@${x.price}`).join("；"), i.note].map(q).join(","));
    }
    shareOrDownload(`發票-${stamp()}.csv`, "﻿" + rows.join("\r\n"), "text/csv");
  };
  $("importInput").onchange = async (e) => {
    const f = e.target.files[0]; e.target.value = ""; if (!f) return;
    try {
      const data = JSON.parse(await f.text());
      const list = Array.isArray(data) ? data : data.invoices;
      if (!Array.isArray(list)) throw new Error("format");
      const fresh = list.filter((inv) => inv && inv.date && !(inv.number && invoices.some((i) => i.number === inv.number)));
      const n = await writeMany(fresh);
      $("settingsSheet").hidden = true;
      toast(`已還原 ${n} 張（重複的已略過）`);
    } catch (err) { toast(err.message === "format" || err instanceof SyntaxError ? "這不是有效的備份檔" : "還原失敗（" + (err.code || err.message) + "）"); }
  };

  render();
  if ("serviceWorker" in navigator && location.protocol === "https:") {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }
})();
