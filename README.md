# 發票記帳

掃描台灣電子發票證明聯的 QR Code，記錄消費日期、金額、品項、店家，依日期分組，可加備註。
網頁版和 iPhone App 登入同一個帳號，資料會即時同步。

| 資料夾 | 內容 |
|---|---|
| `web/` | 網頁版（PWA）：Safari 開網址 →「分享 → 加入主畫面」 |
| `ios/` | 原生 iPhone App（SwiftUI）：GitHub Actions 編譯 .ipa → SideStore 安裝 |
| `firestore.rules` | 雲端資料庫安全規則 |

## 資料保護方式

- 使用 Google Firebase：Email + 密碼登入（Firebase Authentication）、雲端資料庫（Cloud Firestore）。
- 每位使用者的發票存在 `users/{使用者 ID}/invoices/` 底下。
  `firestore.rules` 規定**只有登入的本人**能讀寫自己的資料，其他使用者、未登入者一律拒絕。
- 傳輸使用 HTTPS 加密，Google 伺服器上的資料也有加密儲存。
- 沒網路時資料先存在手機，連線後自動上傳。
- `web/firebase-config.js`、`ios/InvoiceScanner/FirebaseConfig.swift` 裡的值是「專案識別碼」，不是密碼，放在公開 repo 沒關係。安全靠的是上面的規則。
- 注意：Firebase 專案的擁有者（你自己）可以在 Firebase 主控台看到所有資料。如果要讓其他人使用，請告知他們這點。

## 一、建立 Firebase 專案（一次，約 10 分鐘，免費）

1. 到 <https://console.firebase.google.com> 用 Google 帳號登入 →「建立專案」（Google Analytics 可以關掉）。
2. 左側「建構 → Authentication」→「開始使用」→「登入方式」→ 啟用 **電子郵件/密碼**。
3. 左側「建構 → Firestore Database」→「建立資料庫」→ 位置選 **asia-east1（台灣）** →「以正式版模式啟動」。
4. Firestore →「規則」分頁 → 把 `firestore.rules` 的內容整個貼上 →「發布」。
5. 專案設定（齒輪）→「一般」→「你的應用程式」：
   - 新增 **網頁應用程式**（`</>` 圖示）→ 複製 `firebaseConfig` 的值填進 `web/firebase-config.js`。
   - 新增 **iOS 應用程式**，Bundle ID 填 `com.example.InvoiceScanner` → 下載 `GoogleService-Info.plist`，
     把裡面的 `GOOGLE_APP_ID`、`GCM_SENDER_ID`、`API_KEY`、`PROJECT_ID` 填進 `ios/InvoiceScanner/FirebaseConfig.swift`。
     （其他步驟如「新增 SDK」可以略過，專案已經設定好。）
6. Authentication →「設定」→「授權網域」→ 新增 `你的帳號.github.io`。

## 二、網頁版

1. 把專案推到 GitHub（公開 repo）。
2. repo →「Settings → Pages → Source」選 **GitHub Actions**。
3. 「Actions」→ **Deploy Web App** 會自動執行（之後改 `web/` 都會自動部署）。
4. iPhone 用 Safari 開 `https://<帳號>.github.io/<repo 名稱>/` →「分享 → 加入主畫面」。
5. 註冊帳號後就能開始掃描。

## 三、原生 App（SideStore）

1. 推到 GitHub 後，**Build iOS IPA** 會用雲端 Mac 編譯（第一次約 15–20 分鐘，因為要編譯 Firebase），
   完成後到 repo 的「Releases → latest」下載 `InvoiceScanner.ipa`。
2. 第一次安裝 SideStore（需要 Windows，只做一次）：
   iPhone「設定 → 隱私權與安全性 → 開發者模式」打開，再照 <https://docs.sidestore.io> 的官方教學安裝。
3. iPhone 用 Safari 下載 .ipa → 打開 SideStore →「My Apps」→「＋」→ 選 .ipa。
4. 用和網頁版同一個 Email、密碼登入，資料就會同步。
5. 每 7 天打開 SideStore 按「Refresh All」續簽。不用電腦，資料存在雲端，不會遺失。

## 限制
- **店家地址不在發票 QR Code 內**，以統編查經濟部商工登記開放資料（公司登記地址，不一定是門市），可手動修改。
- 部分店家 QR Code 只放部分品項或寫「詳見明細」，需手動補。
- 原生版尚未處理 Big5 編碼的發票，品名可能出現亂碼；網頁版有處理。
