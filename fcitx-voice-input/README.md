# fcitx5 语音输入（vinput）运维与排障

> 按快捷键没反应、出字但没经 AI 整理、要改模型或思考等级时，按「插件 → daemon → ASR → LLM → 回填」分段定位。

## 什么时候用

- 按快捷键完全没反应、不出字。
- 出字了但错字全留着、没经过 AI 整理（**最容易误判**：LLM 失败时 vinput 会退回原始 ASR 文本照常上屏）。
- 要改 LLM 链路 / 模型 / 思考等级，或做无 GUI 的链路实测。

## 链路与配置（2026-09-18 实测核定）

```
Shift+Alt_L → fcitx5 插件 /usr/lib/fcitx5/fcitx5-vinput.so（快捷键在 ~/.config/fcitx5/conf/vinput.conf）
  → DBus org.fcitx.Vinput → vinput-daemon（systemd 用户服务，dbus 激活、不常驻）
  → 本地 sherpa-onnx 流式 ASR（模型在 ~/.local/share/vinput/models）→ LLM 后处理 → 回填焦点窗口
```

配置唯一来源 `~/.config/vinput/config.json`，**一律用 CLI `vinput` 改，别手改 JSON**。当前 LLM：provider `deepseek` → `http://127.0.0.1:8787/v1`（headroom-deepseek，systemd 用户服务）→ api.deepseek.com，key 取 `~/.dsh/.credentials.yaml` 的 `DEEPSEEK_API_KEY`（客户端带 key，headroom 只转发）。场景：`polish`=Markdown 整理（当前激活）/ `__raw__`=纯 ASR / `__command__`=口令改写选中文本。

## A. 按快捷键完全没反应

先看 `vinput daemon status`、`systemctl --user status vinput-daemon --no-pager | head -12`、`vinput daemon log | tail -20`。若日志出现 `error while loading shared libraries: libXXX.so.N` + `status=127`，那是跨仓库升级的 **SONAME 断裂**（升级本身成功），缺的常是传递依赖：

```bash
ldd /usr/bin/vinput-daemon | grep 'not found'     # → libprotobuf-lite.so.36.0.0 => not found
pacman -Qo /usr/lib/libonnxruntime.so.1            # → onnxruntime-cpu（要装重建版）
```

修法（**只装重建版这一个包，不要 `pacman -Sy`**），装完用 `ldd /usr/bin/vinput-daemon | grep 'not found' || echo OK` 与 `systemctl --user restart vinput-daemon && vinput daemon status` 复核：

```bash
sudo pacman -U --noconfirm ~/下载/onnxruntime-cpu-<重建版>-x86_64.pkg.tar.zst
```

其他卡启动原因：ASR 模型文件缺失（`vinput model list` 看已安装/活跃）、`config.json` 被写坏（有 `.bak.*` 可回滚）、麦克风设备名失效。

## B. 出字了，但没经 AI 整理

LLM 段失败时历史里只留 `source:asr` 而无 `source:user`，表现为「语音能用但很蠢」。先 `ss -ltnp | grep 8787` 确认 provider 端点活着，再用 `curl`（带 `--noproxy '*'` 与 `DEEPSEEK_API_KEY`）直打 `http://127.0.0.1:8787/v1/chat/completions`：`HTTP:429` + quota exceeded = 套餐额度用尽；curl 通但 vinput 慢是 headroom 高负载（语音场景用 `deepseek-flash` 更稳）。**别拿 `vinput llm test` 当判据**（约 10s 硬编码超时，链路正常也会误报）。完整 curl 请求体见 SKILL.md §B。

## C. 改链路 / 模型 / 思考等级（一律用 CLI）

```bash
cd ~/.config/vinput && cp -a config.json "config.json.bak.$(date +%Y%m%d-%H%M%S)"   # 先备份
KEY=$(grep -m1 'DEEPSEEK_API_KEY' ~/.dsh/.credentials.yaml | sed -E 's/^[^:]+:\s*//')
vinput llm add deepseek -u http://127.0.0.1:8787/v1 -k "$KEY" -e '{"thinking":{"type":"enabled"},"reasoning_effort":"low"}'
vinput llm rm <旧provider>                                            # 旧的清掉，别留死配置
vinput scene edit polish     -p deepseek -m deepseek-flash --timeout 120000
vinput scene edit __command__ -p deepseek -m deepseek-flash --timeout 120000
vinput scene use polish          # polish=听写+AI整理；__command__=口令改选中文本
systemctl --user restart vinput-daemon && vinput daemon status
```

`-e` 的内容会合并进每次请求体，`low` 是当前思考档位。档位实测（polish 提示词、经 headroom、同机）：flash+thinking+`low` = 1.1s 短句 / 10.0s Markdown 整理（**当前配置**）；关思考 1.3s 最快但只出分条、不做 `##` 归类；`high` 3.8/8.0s；`max` 5.6/22.8s；v4-pro 23~25s 太慢别用。提示词越长越慢：11 条规则 18.6s，精简到 6~7 条后 7~10s。

## D. 无 GUI 实测（灌音法）

虚拟声卡不通（vinput 只列真实硬件输入设备，没有 PipeWire 的 `.monitor`），用声学回路：把测试音频从扬声器放出来让麦克风拾音。

```bash
D=~/.local/share/vinput/models/sherpa-onnx/x-asr-960ms-streaming-zipformer-transducer-zh-en-punct-int8/test_wavs; H=~/.cache/vinput/context.jsonl
before=$(wc -l < "$H"); vinput recording start; sleep 0.7; paplay "$D/1.wav"; sleep 1.5; vinput recording stop -s polish; tail -n +$((before+1)) "$H"
```

出现 `{"source":"llm",...}` = ASR+LLM 整条通；若又看到 `asr` 条目，说明 `raw_cand`/`raw_prev` 被改回 true。房间回放的识别错字是正常现象，验证看链路不看准确率。

## 注意事项

- **LLM 端点一律用本机回环**：daemon 继承 `~/.config/environment.d/99-proxy.conf` 的 `all_proxy=socks5://127.0.0.1:7897`，`no_proxy` 只放行 localhost，远端地址会走 clash 的 socks 而失败。
- `fcitx5-vinput` / `sherpa-onnx` 来自 **archlinuxcn**，protobuf/onnxruntime 来自 **extra**——跨仓库升级最容易 SONAME 断裂。
- 本机 `polish` / `__command__` 均为 `count=1` + 关 raw 候选/预览（`vinput scene edit <场景> --raw-cand false --raw-prev false` 后重启 daemon）→ 说完直接上屏、零手动选择；改回「想手动挑」用 `--raw-cand true`。
- 改提示词前必读 `references/prompts.md`（定稿原文 + 设计依据 + A/B 实测）：四个反复踩的坑——把「要说的话」当指令执行、格式不符预期（要 Markdown 分条）、名词错却不更正、口述顺序本来就乱（要求按逻辑重排，别提「顺序照原文」）。
- `vinput device list` 不含 monitor，填了它不认的名字会**静默回落到默认设备**（表现为抓到的全是静音）；设备名抄 list 原文。daemon `is-enabled` 显示 `disabled` 属正常（dbus 激活，1.4G 内存峰值不值得常驻）。
