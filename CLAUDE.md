# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 溝通

使用者只看臺灣正體中文。所有回覆（含做事途中的進度說明）都用中文，短、講結果。

## 專案組成

兩個獨立的前端，共用同一個 Supabase 專案：

1. **網頁版**：單一 `index.html`（HTML＋CSS＋JS 全在裡面，沒有建置步驟、沒有套件管理），部署在 GitHub Pages：https://jsdryan.github.io/three-day-program/ 。`config.js` 放 Supabase URL 與公開金鑰（資料靠 RLS 保護）。`sw.js` 只負責「休息結束」通知，不快取任何頁面。
2. **Apple Watch 版**：`watch/`，SwiftUI 的 watchOS 獨立 App（沒有 iPhone App），附錶面小工具。

`supabase/schema.sql` 是整個後端：`sessions`（每次訓練一筆）、`prefs`（每人一筆 JSON）、`watch_link` ＋ `claim_watch_link()`（手錶配對）。改 schema 要請使用者到 Supabase SQL Editor 貼上執行。

## 常用指令

網頁版（沒有 lint／測試框架，用瀏覽器實測）：
```bash
python3 -m http.server 8765          # 本機預覽 http://localhost:8765/
git push origin main                 # 推上 main 就是部署（GitHub Pages，約 1 分鐘生效）
```

手錶版（這台 Mac 沒設定 xcode-select，每個指令都要帶 DEVELOPER_DIR）：
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd watch && xcodegen generate        # 新增／刪除 Swift 檔或改 project.yml 後要重跑
# 模擬器編譯
xcodebuild -project WorkoutWatch.xcodeproj -scheme WorkoutWatch -destination 'generic/platform=watchOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
# 真機編譯（generic 目的地不用等手錶連線）＋安裝＋啟動
xcodebuild -project WorkoutWatch.xcodeproj -scheme WorkoutWatch -destination 'generic/platform=watchOS' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008310-00091C493A00E01E build/Build/Products/Debug-watchos/WorkoutWatch.app
xcrun devicectl device process launch --terminate-existing --device 00008310-00091C493A00E01E com.jsdryan.gymplan.watch
```
- `devicectl install` 常常前幾次失敗（連線／DDI 錯誤），重試幾次就好。先確認 xcodebuild 真的 BUILD SUCCEEDED，否則會裝到舊版。
- 免費開發者帳號（Team `Y2PBXKV39D`），手錶上的 App 每 7 天過期，要重新安裝。
- 模擬器測試用的除錯參數（只在 DEBUG）：`xcrun simctl launch <sim> com.jsdryan.gymplan.watch -autostart 0 -autocomplete 2 [-autorest YES -restsec 3] [-showend YES] [-preview 0] [-reset YES]`，登入與課表可用 `simctl spawn … defaults write … snapshot/auth -data <hex>` 塞假資料。讀 App 狀態：`find ~/Library/Developer/CoreSimulator/Devices/<sim>/data/Containers/Data/Application -name com.jsdryan.gymplan.watch.plist`。
- 讀真機上的 App 資料：`xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.jsdryan.gymplan.watch --source Library/Preferences/com.jsdryan.gymplan.watch.plist --destination …`。

## 網頁版架構（index.html）

**課表資料**
- `PROGRAMS`（full／ppl）是內建預設；使用者實際用的是「課表 profile」（`profiles.list`，localStorage `w3-profiles`）。內建的 id 就是 `full`／`ppl`，自建的是 `newId()`。
- 使用者改過的課表存在 `custom[p]`（localStorage `w3-custom-<p>`），沒改過就用 `defDays(p)`。`withIds()` 給每個動作固定 id（`it.id`，當作進行中紀錄的 key）、每一天固定 `did`（歷史紀錄用 `did` 找回這一天「現在」的名稱，所以改天名會同步到舊紀錄）。
- 進行中的每組重量／次數存在 `logs[it.id]`，替代動作存在 `swaps`，key 由 `keyOf(profile)` 決定。
- `effective(it, wk)` 是顯示與存檔的單一入口：套用替代動作（`ALTS`）、自體重量（`isBw`）、綁定器材（`mcOf`）。
- `LIB`（動作庫）、`ALTS`（器材被佔時的替代動作）、`MACHINES`（新莊健身星球的 MaxPump／Npoint 器材；`gym:1` 才會依名稱自動綁定，型錄上的不自動綁）都寫死在 JS 裡。

**歷史紀錄**：`history` 陣列，每筆 `{id: Date.now(), t: ISO, prog, pname, day, did, name, done, total, items:[{n, orig, rm, sets, w, log:[{w,r}], bw?, mc?}], dur?, src?, synced?}`。手錶存的紀錄用同一格式（`src:'watch'`）。

**雲端同步（Supabase）**
- `allPrefs()`／`applyPrefs()`：整包 prefs 上傳／合併。課表清單與自訂課表比 `updated` 時間，新的贏；進行中紀錄以本機為主。
- `pullAll()`：雲端 sessions 補進本機。本機有、雲端沒有的：`synced` 或 `src==='watch'` 代表在別台被刪了 → 本機也刪；從沒上傳成功的才補傳。**不能改回「本機有就補傳」**，那會讓刪掉的紀錄復活。
- `watchSnap()` 會塞進 prefs 的 `watch` 欄位：已套好替代動作、器材、每個動作上次紀錄、每一天 `lastT`。手錶只讀這份，不重寫網頁的邏輯；網頁的課表邏輯改了要確認這份快照還對。

## 手錶版架構（watch/）

- `project.yml`（XcodeGen）定義兩個 target：`WorkoutWatch`（App）與 `StepsWidget`（小工具 extension，裡面有「今天步數」與「下一次訓練」兩個小工具）。兩者靠 App Group `group.com.jsdryan.gymplan` 共用資料。
- `Supa.swift`：直接打 Supabase REST（不用 SDK）。登入流程：網頁「連結 Apple Watch」再用 Google 登入一次，把舊的 refresh token 存進 `watch_link` 並顯示 8 位數配對碼；手錶呼叫 `claim_watch_link` 換 token。免費方案不能改信件範本，所以不用 email OTP。
- `Store.swift`：全部狀態（登入、快照、進行中訓練、休息倒數、步數）都在這裡並存進 UserDefaults；`completeSet()` 處理超級組順序（A 做完直接換 B，B 做完才休息）；`finish(saveHealth:)` 寫 sessions，沒網路就放 `pending` 之後補傳。
- `HealthWorkout.swift`：訓練時開 HKWorkoutSession，讓 App 暗屏也能跑（休息結束要能自己震）；使用者在「結束」畫面選了才存進 Apple 健康。App 被系統關掉重開時用 `recoverActiveWorkoutSession` 接回，避免被切成兩筆。
- 已踩過的坑：
  - 原生 `Picker(.wheel)` 會在開啟時自己停錯格並把錯的重量寫回紀錄，不要用。重量／次數用 `digitalCrownRotation(detent:)`，而且 SetView 剛出現的 0.8 秒內錶冠會送假訊號，靠 `ready` 旗標＋`resync()`（從 store 即時讀值）擋掉。
  - HealthKit 權限每種資料只會問一次；在背景自動要權限不會跳視窗，要讓使用者親手點按鈕觸發，或到 iPhone「健康 → App → 健身課表」手動開。
  - 錶面小工具的更新頻率由 Apple 決定；步數用 HKObserverQuery＋背景傳送觸發重畫，但仍可能落後。
