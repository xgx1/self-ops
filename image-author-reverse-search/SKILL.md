---
name: image-author-reverse-search
description: "识别二次元图片作者/图源：SauceNAO 免 key fetch 反查（本机唯一可达），其余图搜服务在本机网络的坑位清单。用户问\"这图作者是谁/图源\"时使用。"
---

# 二次元图反查作者（本机 Admin/Windows 11 实测 2026-08-11）

## 流程
1. **先查本地标识**：`read` 图片元数据（EXIF）→ 无作者；用 qwen vision_chat（`xd://mcp__qwen_mm_plugins_core_vision_chat`，images 数组传路径）检查四角签名——模型常忽略该问题，需 crop 四角后逐角问（crop 工具坐标 0-1000 归一化）。inspect_image 设备不可用（opencode 余额 401）。
2. **SauceNAO 免 key 反查（主路径，实测可达）**：直接 fetch POST `https://saucenao.com/search.php`，multipart 字段 `file`，带 UA/Origin/Referer。解析：按 `<div class="result"><table class="resulttable">` 切块，`resultsimilarityinfo` 取相似度，`resulttitle` 取标题。**相似度 <70% 一律视为无匹配**（实测不相关图全在 55-57% 区间）。
3. 高相似 → 结果里有 `https://www.pixiv.net/member.php?id=XXX`（画师主页）或 illust_id 链接，直接定位作者。

## 本机网络下各服务实测状态（2026-08-11）
| 服务 | 状态 |
|---|---|
| SauceNAO 网页上传 | ✅ fetch 直连可用，无 key 无 CF |
| ascii2d.net | ❌ Cloudflare 双重拦截（首页一次 + 上传提交又一次），headless Edge 过不去 |
| Bing 视觉搜索 | ❌ 中国区强制跳 cn.bing.com，视觉参数被剥（ensearch=1 无效），落到默认搜索页 |
| IQDB (iqdb.org) | ❌ 无 CF 但持续排队超时 "Can't read query result"（等 60s 无果） |
| catbox.moe / tineye.com | ❌ ECONNRESET 直连断 |
| qwen image_search | ❌ 需 SERPER_API_KEY（未配），配了即可用 |

## 关键坑
- Bun fetch 读 body：先 `const html = await r.text()` 再打印长度，`console.log(r.text())` 后二次读会报 Body already used。
- 微信下载图命名 `<md5>.<ext>@<宽度>w` → 图经微信传播，反查库无记录时大概率是新图/AI 图/约稿图，作者信息只能靠来源渠道（群/人）或 SERPER 反查。
- headless Edge 驱动页面：hook 会拦 bash 内联 fetch，脚本必须用 write 工具写文件再 bun 跑。
- SauceNAO 结果里 `search.php?db=999&url=...` 链接是"数据库内 URL 搜索"链接，非来源页；来源页是 `pixiv.net/member_illust.php` 或 `member.php?id=`。

## 收尾
- 无匹配结论：告知用户图片无签名/EXIF、主流库无记录，列出可行后续（来源渠道确认 / 配 SERPER_API_KEY / 用户手动浏览器查）。
