# 發票記帳

掃描台灣電子發票證明聯的 QR Code，記錄消費日期、金額、品項、店家，依日期分組，可加備註。

同一個專案有兩個版本：

| 資料夾 | 版本 | 安裝方式 |
|---|---|---|
| `web/` | 網頁版（PWA） | Safari 開網址 →「分享 → 加入主畫面」 |
| `ios/` | 原生 iPhone App（SwiftUI） | GitHub Actions 編譯 .ipa → SideStore 安裝 |

## 一、網頁版

1. 把這個專案推到 GitHub（公開 repo。GitHub Pages 免費方案只支援公開 repo；公開的只有程式碼，你的發票資料只存在手機裡）。
2. GitHub repo →「Settings → Pages → Build and deployment → Source」選 **GitHub Actions**。
3. 到「Actions」執行 **Deploy Web App**（之後改 `web/` 會自動部署）。
4. iPhone 用 Safari 開 `https://<帳號>.github.io/<repo 名稱>/`，按「分享 → 加入主畫面」。
5. 從主畫面圖示開啟，第一次掃描時允許相機。

資料存在手機瀏覽器的儲存空間。請定期在「設定與備份」匯出備份檔，存到「檔案」App 或 iCloud Drive。

## 二、原生 App（SideStore）

### 1. 取得 .ipa
推到 GitHub 後，**Build iOS IPA** 會自動用雲端 Mac 編譯（約 5–10 分鐘），
完成後在 repo 的「Releases → latest」下載 `InvoiceScanner.ipa`。
也可以在「Actions → Build iOS IPA → Run workflow」手動執行。

### 2. 第一次安裝 SideStore（需要 Windows 電腦，只做一次）
1. iPhone：「設定 → 隱私權與安全性 → 開發者模式」打開（需重新開機）。
2. 照 SideStore 官方教學 <https://docs.sidestore.io> 安裝，步驟以官方為準。
3. 完成後 iPhone 上會有 SideStore App。

### 3. 安裝發票記帳
1. iPhone 用 Safari 到 Releases 下載 `InvoiceScanner.ipa`（存到「檔案 → 下載項目」）。
2. 打開 SideStore →「My Apps」→ 左上角「＋」→ 選剛下載的 .ipa。

### 4. 每 7 天續簽
打開 SideStore →「My Apps」→ 按「Refresh All」。不需要電腦，資料不會遺失。

## 資料來源與限制
- 發票號碼、日期、金額、賣方統編、品項來自 QR Code；**店家地址不在 QR Code 內**，以統編查經濟部商工登記開放資料（公司登記地址，不一定是門市），可手動修改。
- 部分店家 QR Code 只放部分品項或寫「詳見明細」，需手動補。
- 原生版尚未處理 Big5 編碼的發票，可能出現亂碼；網頁版有處理。
