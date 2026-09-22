// Supabase 連線設定。留空 = 只存在本機、不同步。
// 到 Supabase 專案 → Settings → API 複製：
//   Project URL  → url
//   anon public  → key（這把是公開金鑰，放前端沒問題，資料由 RLS 保護）
window.SB_CONFIG = {
  url: "",
  key: ""
};
