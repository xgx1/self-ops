---
name: local-llm-amd
description: 在本机 AMD 显卡（RX 7900 GRE / gfx1100）上跑本地大模型的选型、部署、性能标定与排障：llama.cpp + ROCm/HIP、Bonsai 2 27B ternary GGUF、显存与上下文预算、Vulkan 后端为什么跑不动、systemd 开机自启、把本地模型接进 DSH 当 provider。触发词：本地大模型、本地模型、跑大模型、本地推理、AMD 跑模型、ROCm、HIP、llama.cpp、Bonsai、Bonsai 2、显存不够、上下文长度、本地模型接 DSH、llama-server。
author: Sx
---

# 本机 AMD 显卡上跑本地大模型（llama.cpp + ROCm）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行，无 Windows 对应方案。
> **基线日期**：2026-09-19 全流程实测通过。

## 一、硬件与预算（先记住这几个数）

| 项 | 值 | 含义 |
|---|---|---|
| GPU | Radeon RX 7900 GRE，Navi 31，**gfx1100**，RDNA3，16368 MiB | 16 GB 显存是硬上限 |
| 显存带宽 | 576 GB/s | 解码速度 ≈ 带宽 ÷ 每 token 读的权重字节 |
| CPU / RAM | Ryzen 9 5950X / 64 GB DDR4-3200 | DDR4 双通道只有几十 GB/s，**层卸载到内存会断崖式变慢** |
| /dev/kfd · renderD128 | 权限 666 / 777 | **不需要把用户加进 render 组** |

选型第一原则：**模型必须整个进显存**。16 GB 卡上「权重 + KV + 视觉塔 + 运行时开销」要全放下。

## 二、选型结论：Bonsai 2 27B（ternary）

同尺寸里最智能且真能装下的只有它——本质是 Qwen3.8-27B（2026-08-14 开源）压到 1.72 bit/权重，保留 98.2% 能力，原生 262K 上下文、多模态、原生 tool calling。

| 候选 | 出局原因 |
|---|---|
| Qwen3.8-27B UD-Q4_K_M | 100K 上下文峰值 23.2 GiB，光权重 17.6 GiB 就超 16 GB 显存 |
| Muse Glimmer-30B | 稠密 30B，4-bit 约 20 GB |
| K2-Horizon-MoVA-36B-A4B | 4-bit 21 GB，且只有 MLX/vLLM 路径，无 GGUF |
| GLM-5.3-Flash | 320B/18B 激活，FP8 权重 306 GiB |
| 任何「4-bit 常规量化」的 27B+ | 亚 4-bit 常规量化会崩（同尺寸 IQ2_XXS 掉到 72.6 分，Bonsai 2 是 84.8） |

## 三、部署（实测可复现）

```bash
# 1. ROCm 运行时（Arch extra 仓库；约 9 GB 安装量，含 rocm-llvm）
#    只装 rocm-hip-runtime 不够：fork 的二进制还要 libhipblas.so.3 / librocblas.so.5
sudo pacman -S --needed rocm-hip-runtime hipblas
rocminfo | grep -m2 -E 'gfx|Marketing'      # 应看到 gfx1100

# 2. fork 预编译二进制（Ubuntu ROCm 7.2 包在 Arch 的 ROCm 7.2.4 上 ABI 兼容，无需自编）
TAG=prism-b10709-9a9394a
curl -L -o llama-rocm.tar.gz \
  "https://github.com/PrismML-Eng/llama.cpp/releases/download/$TAG/llama-$TAG-bin-ubuntu-rocm-7.2-x64.tar.gz"
mkdir -p bin-rocm && tar xzf llama-rocm.tar.gz -C bin-rocm --strip-components=1

# 3. 权重（HF 走 clash 代理；大文件用 -C - 支持断点续传，SSL 断流很常见）
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897
B=https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf/resolve/main
curl -L --retry 5 -C - -o models/Ternary-Bonsai-2-27B-PQ2_0.gguf      "$B/Ternary-Bonsai-2-27B-PQ2_0.gguf"
curl -L --retry 5 -C - -o models/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf "$B/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"

# 4. 跑
export LD_LIBRARY_PATH=$PWD/bin-rocm:/opt/rocm/lib HIP_VISIBLE_DEVICES=0
./bin-rocm/llama-bench -m models/Ternary-Bonsai-2-27B-PQ2_0.gguf -ngl 99 -fa 1
./bin-rocm/llama-server -m models/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  --mmproj models/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf \
  -ngl 99 -fa on -c 102400 --cache-type-k q4_0 --cache-type-v q4_0 \
  --host 127.0.0.1 --port 8081 --alias bonsai2-27b
```

本机既有安装位置：`~/下载/bonsai2-27b/`（`bin-rocm/` 二进制、`models/` 权重、`RUN.md` 实测记录）。

## 四、性能基线（RX 7900 GRE 实测，别用别人的 4090 数字外推）

| 场景 | 数值 |
|---|---|
| 短上下文解码 tg128（PQ2_0） | **42.8 tok/s** |
| 预填充 pp512（PQ2_0） | 409 tok/s |
| 100K 上下文实测 | 灌入 96,192 token，`truncated = 0` |
| 96K 上文下的解码 | 83.15 ms/token = **12.0 tok/s** |
| 96K 上文下的预填充 | 523 → 256 tok/s，均值 253.9 |
| 显存峰值（100K + 视觉塔） | 12,335 MiB / 16,368 MiB |

**长上下文是速度杀手**：短上下文到 96K，解码从 42.8 掉到 12.0 tok/s（每 token 多花约 60 ms），瓶颈从权重带宽转移到 attention 计算。按此斜率推算：64K ≈ 16 tok/s、32K ≈ 23 tok/s（推算值）。**不真需要 100K 就把 `-c` 收到 65536。**

**两个 band 在 RDNA3 上正好相反**（这点和厂商的 Ada/L4 归类不同）：

| band | 体积 | pp512 | tg128 | 选择 |
|---|---|---|---|---|
| `PQ2_0`（2.13 bpw） | 7.21 GB | 409 t/s | **42.8 t/s** | ✅ 交互用这个 |
| `PTQ1_0`（1.75 bpw） | 5.95 GB | 518 t/s | 31.5 t/s | 只在纯批量灌文档时考虑 |

## 五、必踩的坑（按被坑概率排序）

1. **Vulkan 后端跑不动 Bonsai 2**：fork 的 Vulkan 包能认卡（打印 `AMD Radeon RX 7900 GRE (RADV NAVI31)`），但 `PQ2_0` 张量没有 Vulkan 内核 → 退回 CPU。判据：`gpu_busy_percent` 只有个位数、显存只占 1.4 GB、十几个 CPU 线程 99%，一轮 pp512 十几分钟跑不完。**AMD 上必须走 ROCm/HIP。**
2. **Bonsai 2 必须用 PrismML fork**：它要的 Hadamard 激活变换还没进上游，stock llama.cpp 会拒载 `PQ2_0`/`PTQ1_0`；更危险的是 `Q2_0` 会**静默加载然后输出乱码**。权重仓里也没有 mainline 兼容的 g64 文件。
3. **ROCm 依赖要装全**：只装 `rocm-hip-runtime` 时 HIP 后端静默不加载（`--list-devices` 返回 `(none)`），`ldd` 才看得到缺 `libhipblas.so.3` / `librocblas.so.5`。
4. **文件与二进制必须配对**：不匹配会报 `output_norm.weight has offset ...` 这类张量布局错（旧 `Q2_0` 文件已废弃）。
5. **`llama-cli` 没有 `-no-cnv`**：单轮用 `--single-turn`。
6. **HF 大文件下载会 SSL 断流**：永远带 `-C -`，断了重跑即可续传。

## 六、开机自启（systemd user unit）

单元文件全文（`~/.config/systemd/user/bonsai2-llama.service`）：

```ini
[Unit]
Description=Bonsai 2 27B local LLM (llama.cpp + ROCm, Radeon RX 7900 GRE)
After=dev-kfd.device
Wants=dev-kfd.device

[Service]
Type=simple
WorkingDirectory=/home/sx/下载/bonsai2-27b
EnvironmentFile=-%h/.config/bonsai2-llama.env
Environment=LD_LIBRARY_PATH=/home/sx/下载/bonsai2-27b/bin-rocm:/opt/rocm/lib
Environment=HIP_VISIBLE_DEVICES=0
Environment=BONSAI_CTX=102400
Environment=BONSAI_PORT=8081
ExecStart=/home/sx/下载/bonsai2-27b/bin-rocm/llama-server \
  -m models/Ternary-Bonsai-2-27B-PQ2_0.gguf \
  --mmproj models/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf \
  -ngl 99 -fa on \
  -c ${BONSAI_CTX} --cache-type-k q4_0 --cache-type-v q4_0 \
  --host 127.0.0.1 --port ${BONSAI_PORT} --alias bonsai2-27b
Restart=on-failure
RestartSec=15
TimeoutStartSec=600

[Install]
WantedBy=default.target
```

上下文与端口走环境变量，改配置**不要动单元文件**，写 drop-in 或 `~/.config/bonsai2-llama.env`：

```bash
# 临时改上下文（例如只要 64K，省 4 GB 显存）
mkdir -p ~/.config/systemd/user/bonsai2-llama.service.d
printf '[Service]\nEnvironment=BONSAI_CTX=65536\n' > ~/.config/systemd/user/bonsai2-llama.service.d/ctx.conf
systemctl --user daemon-reload && systemctl --user restart bonsai2-llama

systemctl --user status bonsai2-llama       # 看状态
journalctl --user -u bonsai2-llama -f       # 看日志
systemctl --user stop bonsai2-llama         # 腾显存（不会自动重启）
loginctl show-user sx -p Linger             # 必须是 Linger=yes 才能开机自启
```

**开机自启的前提是 linger 打开**（`sudo loginctl enable-linger sx`）——否则用户级服务只在登录后才起。

## 七、接进 DSH 当 provider

本地 llama-server 是 OpenAI 兼容接口，用 `llm-pi-ai` 适配器接（`~/.dsh/settings.yaml`）：

```yaml
llm-pi-ai:
  providers:
    local-bonsai:
      displayName: Bonsai 2 27B (local)
      api: openai-completions
      baseURL: http://127.0.0.1:8081/v1
      headers: { Authorization: "Bearer local-no-auth" }   # 见下方坑
      models:
        - id: bonsai2-27b
          name: Bonsai 2 27B (local AMD)
          contextWindow: 102400
          maxTokens: 32768
```

- **keyless 本地服务也必须给占位凭据**：pi-ai 的 `openai-completions` 实现强制要求 API key 或 `Authorization` 头，光省掉 `apiKeyEnv` 会在请求时被拒。用 `headers.Authorization` 最省事。
- provider id 用小写连字符（`local-bonsai`），别用大写/下划线。
- 改完 `settings.yaml` **不用重启 DSH**：适配器按请求解析配置。
- 选模型走会话里的模型选择器；不要改 `agent-default-model`（本地 27B 比云端主力模型弱，只适合当离线/隐私场景的备选）。

## 八、思考档位（可调节）

Bonsai 2 的思考强度**不是自由参数**，取值由模型自带的 chat template 定死。权威判据是服务端 `/props` 里的 `chat_template`：

```
{%- set resolved_reasoning_effort = reasoning_effort|default('xhigh') %}
{%- if resolved_reasoning_effort not in ('xhigh', 'medium', 'low') %}
{{- raise_exception('Unexpected reasoning effort ...') }}
```

**只认 `xhigh`（默认）/ `medium` / `low` 三档；传别的（含 `high`）模板直接抛异常 → llama-server 回 HTTP 500。**

| 请求里的字段 | 实测效果 |
|---|---|
| `reasoning_effort: none` | ✅ 思考关闭（llama-server 自己翻译成 `enable_thinking=false`） |
| `reasoning_effort: low` / `medium` | ✅ 生效，思考长度明显不同 |
| `reasoning_effort: xhigh` | ✅ 等同不传（模板默认档） |
| `reasoning_effort: high` | ❌ 500 `Unexpected reasoning effort high` |
| `chat_template_kwargs: {enable_thinking: false}` | ✅ 思考关闭 |
| `thinking_budget_tokens: N` | ❌ 无效（服务端不认，别照 Bonsai 文档抄） |
| `thinking: {type: disabled}` | ❌ 无效（那是 DeepSeek 的协议，不是它的） |

### 映射进 DSH

`reasoningEfforts` 的**键**是菜单档位（DSH 认 off/minimal/low/medium/high/xhigh/max），**值**就是发到线上的 `reasoning_effort`；未声明的档位会变成 `null` 而被隐藏，所以菜单里只出现声明过的。

```yaml
      reasoning: medium          # 会话未选档位时的默认，务必显式给
      models:
        - id: bonsai2-27b
          reasoningEfforts:
            "off": none          # 注意引号：不加会被 YAML 1.1 解析成布尔 false
            low: low
            medium: medium
            xhigh: xhigh
```

两个容易踩的点：

- **`off` 的键必须加引号**。`off` 在 YAML 1.1 里是布尔假，不引号会变成键 `false`，档位静默消失。
- **路由级 `reasoning` 一定要显式给**。pi-ai 在「会话没选档位」时会把 `thinkingLevelMap.off` 当 `reasoning_effort` 发出去；配了 `off: none` 却不给默认档，等于**默认静默关闭思考**（和模型自带 xhigh 默认相反）。
- 无需配 `compat.supportsReasoningEffort`：它对手写路由默认就是 `true`（只有 Grok/Zai/Moonshot/Together/Cloudflare/NVIDIA/AntLing 例外）。
- 请求到不了模型它不会报错——`reasoning_effort` 走的是「值即档位」约定，配错值表现为运行期 500，所以**改完要实测一档**。

## 九、排障速查

| 症状 | 先查 |
|---|---|
| HIP 后端没加载、`--list-devices` 空 | `ldd bin-rocm/*.so \| grep 'not found'`，缺库补 `hipblas` |
| 显存不够 / OOM | 降 `-c`（KV 按 18 KiB/token@q4_0 算）、去掉 `--mmproj`、加 `--no-mmproj-offload` 把视觉塔放内存 |
| 速度只有个位数 tok/s | 确认 `-ngl 99` 真的生效（看启动日志），显存占用是否只有一两 GB（说明没卸载到 GPU） |
| 输出是乱码 | 用错二进制（stock llama.cpp）或文件/二进制不配对 |
| 换档位后 500 报错 | 传了模板不认的值（只有 xhigh/medium/low 合法），看 `/props` 的 chat_template |
| 模型不思考了 | 检查是否配了 `off: none` 但没给路由级 `reasoning` 默认档 |
| `error: invalid argument` | 参数名对不上，先在 `--help` 里确认 |
