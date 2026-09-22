# 跨裝置同步設定（Supabase + Google / Apple 登入）

網頁：https://jsdryan.github.io/three-day-program/
程式碼已經接好，只差三個外部設定。全部做完大約 20 分鐘，Apple 部分需要付費的 Apple Developer 帳號。

## 1. 建 Supabase 專案（免費）
1. https://supabase.com → Sign in（用 GitHub 登入最快）→ New project。
2. 名稱隨意，Region 選 Northeast Asia (Tokyo)，設一個資料庫密碼（記下來，之後不太會用到）。
3. 左側 SQL Editor → New query → 貼上本 repo 的 `supabase/schema.sql` 全部內容 → Run。
4. 左側 Settings → API：複製 **Project URL** 和 **anon public** key。

## 2. 開啟 Google 登入
1. https://console.cloud.google.com → 建一個專案 → APIs & Services → OAuth consent screen → External → 填 App 名稱和你的 email → 儲存。
2. Credentials → Create Credentials → OAuth client ID → Web application。
   - Authorized JavaScript origins：`https://jsdryan.github.io`
   - Authorized redirect URIs：`https://<你的專案 ref>.supabase.co/auth/v1/callback`
     （這個網址在 Supabase → Authentication → Providers → Google 頁面上會直接顯示，照抄）
3. 拿到 Client ID 和 Client Secret → 回 Supabase → Authentication → Providers → Google → 開啟，貼上兩個值 → Save。

## 3. 開啟 Apple 登入（需要 Apple Developer Program，每年 US$99）
1. https://developer.apple.com/account → Certificates, Identifiers & Profiles。
2. Identifiers → 建一個 App ID（勾 Sign in with Apple）。
3. Identifiers → 建一個 Services ID（例如 `com.jsdryan.workout.web`），勾 Sign in with Apple → Configure：
   - Domains：`<你的專案 ref>.supabase.co`
   - Return URLs：`https://<你的專案 ref>.supabase.co/auth/v1/callback`
4. Keys → 建一個 Key，勾 Sign in with Apple，選剛才的 App ID → 下載 .p8 檔（只能下載一次）。
5. 回 Supabase → Authentication → Providers → Apple → 開啟：
   - Client IDs：填 Services ID（`com.jsdryan.workout.web`）
   - Secret Key：Supabase 頁面有「Generate secret」工具，用 Team ID、Key ID、.p8 內容產生 → 貼上 → Save。
   （Apple 的 secret 六個月會過期，到期要重新產生一次。）

## 4. 設定網址
Supabase → Authentication → URL Configuration：
- Site URL：`https://jsdryan.github.io/three-day-program/`
- Redirect URLs：加入 `https://jsdryan.github.io/three-day-program/`

## 5. 把金鑰填進網頁
編輯 repo 根目錄的 `config.js`，把第 1 步拿到的兩個值填入：
```js
window.SB_CONFIG = {
  url: "https://xxxx.supabase.co",
  key: "eyJ..."
};
```
推上 main，30 秒後網頁上方會出現「Google 登入」「Apple 登入」按鈕。
（anon key 是設計給前端用的公開金鑰，資料存取靠 schema.sql 裡的 RLS 限制只能讀寫自己的。）

## 同步方式
- 登入後：先把雲端和本機的紀錄合併（以每筆紀錄的 id 聯集），之後每次「完成訓練」、改重量、換動作、刪紀錄都會即時上傳。
- 另一支手機登入同一個帳號打開網頁就會拉下來。
- 沒登入：行為和以前一樣，只存本機。

## iPhone 加到主畫面的注意事項
從主畫面圖示開啟時登入，會跳到瀏覽器完成 Google/Apple 授權。如果授權完沒有跳回來、或回來還是顯示未登入，改用 Safari 直接開網址登入一次再使用。
