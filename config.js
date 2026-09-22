// Supabase 連線設定。這兩個值是設計給前端用的公開值，資料靠 RLS 保護。
window.SB_CONFIG = {
  url: "https://wxmgriibfvteeqsfjyhe.supabase.co",
  key: "sb_publishable_tpCUAAz35Qqk8JyUK4Ovnw_VkLfgm4P",
  // 已在 Supabase 開啟的第三方登入。Apple 需加入 Apple Developer Program 後才能加上 "apple"
  providers: ["google"]
};
