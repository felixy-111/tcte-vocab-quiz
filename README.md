# 統測字彙練習

單檔 PWA（可安裝到手機主畫面的網頁 app），給家教老師太一用的統測字彙教學工具。
一句話：**紙本測驗卷批改後記錄錯題，學生手機線上寫題，錯題自動追蹤。**

兩個入口：

- **老師模式**（雲端模式需登入、本機模式免登入）：對答案、錯題總覽、出卷、學生管理、設定
- **學生練習**（免登入）：輸入卷代碼或自由練習，交卷即批改，累積錯題與 streak

---

## 架構圖（文字版）

```
                       ┌─────────────────────────┐
                       │  index.html（單檔 app）  │
                       │  HTML + CSS + JS 全內嵌  │
                       └───────────┬─────────────┘
                                   │
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
   題庫（唯讀）              本機資料層                    雲端層（選用）
   data/manifest.json      localStorage:tsvt_db        Supabase（三張表）
   data/u1_upper.json       students / assignments      students / assignments
   data/u1_lower.json       / attempts                  / attempts + RLS
        │                          │                          │
   fetch 按需載入          先寫本機、馬上可用          有網路自動同步、
   配合題展開成 10 小題      （離線也能跑）             離線改動排隊補送
```

- **題庫**：只讀現有 JSON，不放參考書原文或真題原文。配合題（matching）在載入時展開成 10 小題，
  `question_id = {題組id}#{1-10}`，方便逐字統計錯題。
- **本機優先**：所有操作先寫 localStorage、畫面立即更新；接上雲端後才在背景同步（last-write-wins 合併）。
- **離線**：Service Worker 快取核心檔案，沒網路也開得起來；Supabase 網域一律走網路、不快取。

---

## 檔案說明

| 檔案 | 用途 |
|---|---|
| `index.html` | 整個 app（HTML/CSS/JS 全在裡面） |
| `manifest.webmanifest` / `sw.js` | PWA 安裝與離線快取 |
| `icon-192.png` / `icon-512.png` / `apple-touch-icon.png` | App 圖示（深藍底白字「統測字彙」） |
| `schema.sql` | Supabase 資料表設定檔（雲端模式才需要） |
| `vendor/supabase.js` | Supabase JS SDK（本地保存版，不吃 CDN；離線也載得到、避開 CDN 投毒） |
| `data/manifest.json` | 題庫清單（有哪幾卷、對應哪個檔） |
| `data/u1_upper.json` / `data/u1_lower.json` | 題庫（從上層 `題庫/` 複製而來） |

### 新增題庫的方式

把新的題庫 JSON 放進 `data/`，再到 `data/manifest.json` 補一列：

```json
{ "file": "u2_upper.json", "unit": 2, "half": "upper", "label": "Unit 2（上）", "papers": ["review", "quiz"] }
```

`sw.js` 的 `ASSETS` 也把新檔加進去（想讓它離線可用的話），並把 `CACHE` 版本號 +1。

---

## 兩種模式

### 本機模式（預設，零設定）

`index.html` 最上方的 `CONFIG` 兩個欄位留空，就是本機模式：

- 不用登入，打開就能用，**所有功能都在**（對答案、出卷、學生模式寫卷、匯出／匯入 JSON）
- 資料存在**這台裝置的瀏覽器**裡（localStorage，key = `tsvt_db`）
- 缺點：換裝置、換瀏覽器資料不會跟著走 → 用「學生 → 匯出 JSON」手動搬（本機模式另有「匯入 JSON」）

> 太一目前還沒建 Supabase 專案，就是跑在本機模式。所有功能都能用，之後要跨裝置再接雲端即可。

### 雲端模式（跨裝置同步）

接上 Supabase（免費雲端資料庫）後，手機和電腦看同一份資料。平常照樣先寫本機、馬上可用；
有網路時自動同步上雲，離線時的改動先排隊、恢復連線後補送。左上角徽章可點，會用白話說明同步狀態。

---

## Supabase 設定步驟（一次性，約 10 分鐘）

1. **建立免費專案**：到 [supabase.com](https://supabase.com) 註冊 → New Project（區域選 Tokyo 或 Singapore 較快）
2. **建資料表**：左側 SQL Editor → 貼上本資料夾的 `schema.sql` 全文 → Run
3. **建老師登入帳號**：
   - **⚠️ 必做：關閉自助註冊。** Authentication → Sign In / Providers → Email → 把「**Allow new users to sign up**」關掉。
     不關的話，**任何知道網址的人都能自己註冊帳號、變成有全權的老師**，讀寫全部學生與成績。
   - 同一頁把「Confirm email」也關掉（自己手動建帳號，不用收確認信）
   - Authentication → Users → **Add user** → 填自己的 Email＋密碼（這就是老師登入 app 的帳號；只手動建你自己一個）
4. **填入金鑰**：Settings → API 頁面，複製兩個值，貼進 `index.html` 最上方的 `CONFIG`：

   ```js
   const CONFIG = {
     SUPABASE_URL: "https://xxxx.supabase.co",   // Project URL
     SUPABASE_ANON_KEY: "eyJhbGci..."            // anon public key
   };
   ```

5. **登入**：重新打開 app → 老師模式會出現登入畫面，輸入第 3 步的帳密。每台裝置登入一次即可。

### 為什麼學生端不用登入也安全？

`schema.sql` 的 RLS（資料列安全鎖）設計：

- **老師（登入後 authenticated）**：三張表全權讀寫。
- **學生端（未登入 anon）**：
  - `students`：只能 **SELECT** → 學生端**看得到整份學生名單**（挑自己的名字用），所以**名字請用暱稱**（見下）
  - `assignments`：只能 **SELECT** → 學生端**看得到卷的內容與代碼**（用代碼開卷用）
  - `attempts`：只能 **INSERT**，且限 `mode='online'`（交卷寫自己的線上作答）；**不能讀、不能改、不能刪**，紙本批改（paper）也寫不了（只有老師能寫）
- 白話總結：學生端**能讀到學生名單與卷資訊、能寫入自己的作答，但讀不到、也改不了任何人的成績**。
  就算 anon key 外洩，最多也只是看到暱稱名單與題目，動不了任何成績紀錄。

> ⚠️ **提醒**：學生名字建議用**暱稱**（如「小明」「A 同學」），不要用全名。
> 因為學生端（anon）能 SELECT `students` 表，用全名等於把班上名單攤在前端。

---

## Self-test（回歸測試）

打開 `index.html?selftest=1`，會**直接呼叫核心邏輯**跑一輪完整流程
（建學生 → 對答案 → 錯題總覽 → 出卷 → 線上交卷 → streak → 匯出 JSON → 清理），
畫面與 console 會列出每步 PASS/FAIL 摘要。測試資料跑完會自動清掉，不污染真實 localStorage。
改完程式想快速確認沒改壞，跑這個最快。

---

## 功能 Roadmap（依此順序）

1. **錯題 SRS 今日複習**：把答錯的字排進間隔複習（1 / 3 / 7 / 16 / 35 天），首頁顯示「今天要複習 N 個字」。
2. **真題高頻字出題權重**：讀 `exam_stats.json`（統測真題高頻字統計），出卷時高頻字權重加倍。
3. **每週學習報告 + 家長訊息**：自動整理該週作答量、正確率、進步幅度，一鍵複製傳家長（照 scheduler 的家長訊息格式）。
4. **仿真題模式**：加入同義字辨識題型、克漏字迷你版（僅用現有題庫詞彙自組，不放真題原文）。
5. **Web Speech 單字發音**：作答／複習時可點單字聽發音（瀏覽器內建語音，免 API）。
6. **統測倒數儀表板**：首頁顯示距離統測天數 + 本週進度環。
