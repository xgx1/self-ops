# fcitx5 语音输入（vinput）—— 技能导航

排障入口：**先读 `SKILL.md` 的「先判一句话：现在到底能用吗」**，用 daemon journal 配对录音起止量字/秒，
就能判定 ASR 这段是不是好的。

## 什么时候用这个技能

- 按 `Shift+Alt_L` 完全没反应、不出字。
- 出字了但错字全留着、像没经过 AI 整理（**最容易误判**：LLM 段失败时 vinput 会退回原始 ASR 文本照常上屏）。
- 说一大段只回来几个字、结果像半截。
- 要改 LLM 链路 / 模型 / 思考等级 / 提示词，或做无 GUI 的链路实测。

## 文档结构

| 文件 | 内容 |
|---|---|
| `SKILL.md` | 主文档：判据、现状、日志可读性、debug 开关、LLM 请求真实形态、三个症状、改配置、延迟实测、坑位、不确定清单 |
| `references/prompts.md` | 两份提示词定稿原文（可恢复副本）+ 五个失败模式的设计依据 + 恢复命令 |

## 三个最容易走错的方向

1. **别找 `~/.cache/vinput/context.jsonl`。** 本机从未出现过，也没有配置开关能写它。
   daemon journal 是唯一活信号，但**非 debug 模式下 LLM 段成功没有任何日志**。
2. **别拿 `vinput llm test` 当判据。** 它约 10s 硬编码超时，链路正常也会误报
   `Timeout was reached`；真正的 LLM 请求超时是 60s。
3. **改提示词前先看「LLM 请求的真实形态」。** daemon 会把提示词包进一段 JSON 契约
   （`{"candidates":[...]}` + `response_format:json_object`），提示词不是原样发出去的；
   `returned no valid candidates` 就是契约没被遵守。

## 快速坐标

```
快捷键  Shift+Alt_L（[TriggerKey]，~/.config/fcitx5/conf/vinput.conf）
配置    ~/.config/vinput/config.json（明文含 key；一律用 CLI vinput 改，改完 restart daemon）
模型    x-asr-1920ms-streaming-zipformer-transducer-zh-en-punct → ~/.model/vinput/
LLM     provider deepseek → 127.0.0.1:8787（headroom-deepseek）→ api.deepseek.com
场景    polish（激活，Markdown 整理）/ __raw__ / __command__
版本    fcitx5-vinput 2.3.26-1
```

## 注意

技能正文只写有实锤的内容（本机 journal / 配置 / CLI 帮助均可复核）。
无证据的旧结论一律删掉或移入「不确定 / 待确认」，不做推测性补充。
