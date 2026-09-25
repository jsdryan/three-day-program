import Foundation

// 跟網頁版 config.js 同一個 Supabase 專案（公開金鑰，資料靠 RLS 保護）
enum Config {
    static let supabaseURL = URL(string: "https://wxmgriibfvteeqsfjyhe.supabase.co")!
    static let supabaseKey = "sb_publishable_tpCUAAz35Qqk8JyUK4Ovnw_VkLfgm4P"
}
