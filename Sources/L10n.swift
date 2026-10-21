import Foundation

/// 极简本地化层：以中文原文为 key，英文环境返回映射值
enum L10n {
    static var language: String { Preferences.shared.language }
    static var isEnglish: Bool { language == "en" }

    static func t(_ zh: String) -> String {
        guard isEnglish, let en = enMap[zh] else { return zh }
        return en
    }

    static let enMap: [String: String] = [
        // 通用 / 设置
        "账号": "Account",
        "用户": "User",
        "添加账号": "Add Account",
        "添加账号…": "Add Account…",
        "管理账号…": "Manage Accounts…",
        "编辑": "Edit",
        "删除": "Delete",
        "编辑账号": "Edit Account",
        "保存": "Save",
        "取消": "Cancel",
        "测试连接": "Test Connection",
        "测试中…": "Testing…",
        "连接成功": "Connected",
        "密码": "Password",
        "套餐": "Plan",
        "查看全部套餐": "View All Plans",
        "展开": "Expand",
        "套餐生效时间范围": "Plan Period",
        "外观": "Appearance",
        "设置栏大小": "Settings Size",
        "菜单栏大小": "Menu Bar Size",
        "整体外观": "Theme",
        "跟随系统": "System",
        "浅色": "Light",
        "深色": "Dark",
        "通用": "General",
        "刷新间隔": "Refresh",
        "30 秒": "30 s",
        "60 秒": "60 s",
        "2 分钟": "2 min",
        "5 分钟": "5 min",
        "菜单栏显示": "Menu Bar Shows",
        "剩余 %": "Remaining %",
        "已用 %": "Used %",
        "剩余 AFP": "Remaining AFP",
        "菜单栏选项": "Popover",
        "余量 + 模型用量": "Quota + Usage",
        "仅余量统计": "Quota only",
        "仅模型用量": "Usage only",
        "开机自动启动": "Launch at Login",
        "版本": "Version",
        "语言": "Language",
        "简体中文": "简体中文",
        "English": "English",
        "尚未添加账号": "No account yet",
        "还没有账号，点击下方「添加账号」，填入 API 访问密钥的账号与密码即可。": "No account yet. Click “Add Account” below and fill in your API Access Key ID and Secret.",
        "使用火山引擎 API 访问密钥（账号 + 密码）登录，可在同一台机器上保存多个账号并随时切换。": "Sign in with a Volcengine API key (Access Key ID + Secret). Multiple accounts are supported and can be switched anytime.",
        "Access Key ID，通常以 AKLT 开头": "Access Key ID (usually starts with AKLT)",
        "Secret Access Key（留空则不修改）": "Secret Access Key (leave blank to keep)",
        "这两项是火山引擎「访问控制 → API 访问密钥」里的 Access Key ID 与 Secret Access Key，不是控制台登录用的手机号/密码。": "These are the Access Key ID and Secret Access Key from Volcengine Console → Access Control → API Access Keys — not your console login credentials.",
        "AK/SK 在火山引擎控制台「API 访问密钥」中创建；Secret Key 仅保存在本机钥匙串。": "AK/SK are created under Console → API Access Keys. The Secret Key is stored only in the local Keychain.",
        "从剪贴板粘贴": "Paste from Clipboard",

        // 面板
        "未登录": "Not signed in",
        "登录": "Sign in",
        "正在读取用量…": "Loading usage…",
        "暂无额度数据": "No quota data",
        "燃料值(AFP)用量": "Fuel (AFP) Usage",
        "今日模型用量": "Today's Model Usage",
        "超额": "Overage",
        "自动续费": "Auto-renew",
        "退出": "Quit",
        "立即刷新": "Refresh now",
        "设置…": "Settings…",
        "关于 ArkWatch": "About ArkWatch",
        "套餐信息，可在设置中查看全部套餐": "Plan info — see Settings for all plans",
        "5 小时": "5 h",
        "一周": "Week",
        "一月": "Month",
        "今日": "Today",
        "近 5 小时": "Last 5 h",
        "近一周": "Last 7 days",
        "近一月": "Last 30 days",
        "未绑定": "Not linked",
        "无": "None",
        "已开通 · %@": "Active · %@",
        "未开通": "Inactive",
        "检测中": "Checking",
        "查看中": "Viewing",
        "到期 %@": "Expires %@",
        "更新 %@": "Updated %@",
        "已用 %@ / %@ AFP": "Used %@ / %@ AFP",
        "剩余": "Remaining",
        "已用": "Used",
        "即将重置": "Resetting soon",
        "%d 天 %d 小时后重置 · %@": "%d d %d h until reset · %@",
        "%d 小时 %d 分后重置 · %@": "%d h %d m until reset · %@",
        "%d 分钟后重置 · %@": "%d min until reset · %@",
        "打开火山方舟 Agent Plan 订阅页": "Open the Ark Agent Plan subscription page",

        // 套餐页
        "全部套餐": "All Plans",
        "含视频生成": "Video included",
        "切换": "Switch",
        "开通": "Subscribe",
        "打开控制台": "Open Console",
        "以控制台为准": "See console",
        "按 5 小时 / 周窗口限流，额度见控制台": "Rate-limited per 5h/week window; see console for quota",
        "面向 Agent 场景，含模型与 Harness 额度": "For agent use cases, incl. models and harness quota",
        "面向编程工具，按 5 小时 / 周窗口限流": "For coding tools, rate-limited per 5h/week window",
        "点「开通」会在浏览器打开火山方舟控制台的开通管理页，可查看额度、购买或续费。": "Click “Subscribe” to open the Ark console page, where you can view quota, purchase or renew.",
        "说明：接口只能读取已购买的那一档。「切换」仅切换本机查看对象，不会改变实际订阅；真正变更套餐请在控制台购买或升配。": "Note: the API only returns the purchased tier. “Switch” only changes what this app displays; it does not change your subscription.",
        "¥40 / 月": "¥40 / mo",
        "¥200 / 月": "¥200 / mo",
        "¥500 / 月": "¥500 / mo",
        "¥1,000 / 月": "¥1,000 / mo",
        "月 20,000 · 周 7,000 · 5 小时 2,000 AFP": "Month 20,000 · Week 7,000 · 5 h 2,000 AFP",
        "月 100,000 · 周 35,000 · 5 小时 10,000 AFP": "Month 100,000 · Week 35,000 · 5 h 10,000 AFP",
        "月 250,000 · 周 87,500 · 5 小时 25,000 AFP": "Month 250,000 · Week 87,500 · 5 h 25,000 AFP",
        "月 500,000 · 周 175,000 · 5 小时 50,000 AFP": "Month 500,000 · Week 175,000 · 5 h 50,000 AFP",

        // 提示与错误
        "当前账号未查询到生效中的套餐": "No active plan found for this account",
        "响应解析失败：%@": "Failed to parse response: %@",
        "网络请求失败：%@": "Network error: %@",
        "无 HTTP 响应": "No HTTP response",
        "%@（请检查 AK/SK 是否正确、系统时间是否准确）": "%@ (check your AK/SK and system clock)",
        "非 JSON 响应": "Non-JSON response",
        "GetAFPUsage 未返回 AFPF* 字段": "GetAFPUsage returned no AFPF* fields",
        "账号「%@」缺少 Secret Key，请重新编辑账号": "Account “%@” is missing its Secret Key — please edit it",
        "连接成功 · %@ %@ · %@": "Connected · %@ %@ · %@",
        "连接成功，但该账号没有生效中的 Agent/Coding Plan 套餐": "Connected, but this account has no active Agent/Coding Plan",
        "连接失败：%@": "Connection failed: %@",
        "该账号缺少 Secret Key，请在设置中重新绑定": "Secret Key missing — please re-link it in Settings",
        "尚未绑定 AK/SK，请在设置中完成绑定后即可读取用量": "No AK/SK linked yet — complete it in Settings to load usage",

        // 菜单栏 / 窗口
        "ArkWatch · 未登录": "ArkWatch · Not signed in",
        "火山方舟套餐": "Ark Plans",
        "本月 %.0f / %.0f AFP": "This month %.0f / %.0f AFP",
        "重置 %@": "Reset %@",
        "Ark 无": "Ark —",
        "火山方舟用量菜单栏监控": "Menu-bar usage monitor for Volcengine Ark",
        "设置": "Settings"
    ]
}

func L(_ zh: String) -> String { L10n.t(zh) }

func Lf(_ zh: String, _ args: CVarArg...) -> String {
    String(format: L10n.t(zh), arguments: args)
}
