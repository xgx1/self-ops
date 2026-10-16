---
name: local-llm-amd
description: 在本机 AMD 显卡（RX 7900 GRE / gfx1100）上跑本地大模型的选型、部署、性能标定与排障：llama.cpp + ROCm/HIP、显存与上下文预算、Vulkan 后端为什么不能用、systemd 开机自启、把本地模型接进 DSH 当 provider。触发词：本地大模型、本地模型、跑大模型、本地推理、AMD 跑模型、ROCm、HIP、llama.cpp、显存不够、上下文长度、本地模型接 DSH、llama-server。
author: Sx
---

# 本机 AMD 显卡上跑本地大模型（llama.cpp + ROCm）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行，无 Windows 对应方案。
> **基线日期**：2026-09-19 全流程实测通过；2026-10-15 改为模型无关写法（原 GGUF 案例已弃用）。

## 一、硬件与预算（先记住这几个数）

| 项 | 值 | 含义 |
|---|---|---|
| GPU | Radeon RX 7900 GRE，Navi 31，**gfx1100**，RDNA3，16368 MiB | 16 GB 显存是硬上限 |
| 显存带宽 | 576 GB/s | 解码速度 ≈ 带宽 ÷ 每 token 读的权重字节 |
| CPU / RAM | Ryzen 9 5950X / 64 GB DDR4-3200 | DDR4 双通道只有几十 GB/s，**层卸载到内存会断崖式变慢** |
| /dev/kfd · renderD128 | 权限 666 / 777 | **不需要把用户加进 render 组** |

选型第一原则：**模型必须整个进显存**。16 GB 卡上「权重 + KV + 视觉塔 + 运行时开销」要全放下。
先按 `权重字节 ≈ 参数量 × 量化位数 ÷ 8` 算一遍，再减 KV 与运行时（Q4 的 27B 稠密模型光权重就 17+ GB，直接出局）。

## 二、选型判据

| 判据 | 说明 |
|---|---|
| 权重能全进 16 GB | 首选 MoE（激活参数小）或亚 4-bit 极端量化 |
| 有 GGUF | 只有 MLX/vLLM 路径的模型跑不了 llama.cpp |
| 量化位宽别乱降 | 常规量化的 27B+ 压到亚 4-bit 会明显掉分；ternary/1-bit 类专用量化是另一条路，但要专用 fork 才认（见下） |
| 上下文预算 | KV 按 q4_0 每 token 约 18 KiB 估（27B 量级）；100K 上下文约 1.8 GB，出预算就砍 `-c` |
| 现成真机数字 | 只信同卡实测，别用 4090/L4 的数字外推（见第四节） |

## 三、部署（可复现流程）

```bash
# 1. ROCm 运行时（Arch extra 仓库；约 9 GB 安装量，含 rocm-llvm）
#    只装 rocm-hip-runtime 不够：ROCm 版 llama.cpp 还要 libhipblas.so.3 / librocblas.so.5
sudo pacman -S --needed rocm-hip-runtime hipblas
rocminfo | grep -m2 -E 'gfx|Marketing'      # 应看到 gfx1100

# 2. llama.cpp 的 ROCm 二进制
#    优先官方 release 的 ubuntu-rocm 包（Ubuntu ROCm 包在 Arch 的 ROCm 上 ABI 兼容，无需自编）；
#    若模型的量化格式只有某 fork 认，就用该 fork 的 release（先读它的 README 确认支持矩阵）
TAG=<release-tag>
curl -L -o llama-rocm.tar.gz \
  "https://github.com/<owner>/llama.cpp/releases/download/$TAG/llama-$TAG-bin-ubuntu-rocm-7.2-x64.tar.gz"
mkdir -p bin-rocm && tar xzf llama-rocm.tar.gz -C bin-rocm --strip-components=1

# 3. 权重（HF 走 clash 代理；大文件用 -C - 支持断点续传，SSL 断流很常见）
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897
curl -L --retry 5 -C - -o models/<model>.gguf "<hf-resolve-url>"

# 4. 跑
export LD_LIBRARY_PATH=$PWD/bin-rocm:/opt/rocm/lib HIP_VISIBLE_DEVICES=0
./bin-rocm/llama-bench -m models/<model>.gguf -ngl 99 -fa 1
./bin-rocm/llama-server -m models/<model>.gguf \
  -ngl 99 -fa on -c 102400 --cache-type-k q4_0 --cache-type-v q4_0 \
  --host 127.0.0.1 --port 8081 --alias local-model
```

安装位置按用户约定落 `~/.model/<模型名>/`，别散在 `~/下载`。

## 四、性能基线方法

**必须自己测**——同卡同模型的数字才有意义。`llama-bench` 至少跑一遍：

```bash
./bin-rocm/llama-bench -m models/<model>.gguf -ngl 99 -fa 1 -p 512 -n 128
```

判据与经验：

- 解码速度上限约 = 显存带宽 ÷ 每 token 读取的权重大小；实测远低于这个上限说明权重没全上卡。
- **长上下文是速度杀手**：短上下文到接近满上下文，解码会掉到 1/3 甚至更低（瓶颈从权重带宽转到 attention 计算）。按实测斜率推自己要的 `-c`，**不真需要长上下文就砍**。
- 量化档之间在 RDNA3 上不按常规规律排（显存与算力权衡）。同一模型有多个量化文件时，两个都 bench 一遍再定，别照别人的表选。

## 五、必踩的坑（按被坑概率排序）

1. **AMD 上必须走 ROCm/HIP，不要指望 Vulkan**：Vulkan 后端能认卡（打印 `AMD Radeon RX 7900 GRE (RADV NAVI31)`），但 fork/冷门量化格式常缺 Vulkan 内核 → 静默退回 CPU。判据：`gpu_busy_percent` 个位数、显存只占一两 GB、CPU 线程 99%。
2. **ROCm 依赖要装全**：只装 `rocm-hip-runtime` 时 HIP 后端静默不加载（`--list-devices` 返回 `(none)`），`ldd` 才看得到缺 `libhipblas.so.3` / `librocblas.so.5`。
3. **权重文件与二进制必须配对**：不匹配会报 `output_norm.weight has offset ...` 这类张量布局错。专用量化（ternary/1-bit）多半要专用 fork，stock llama.cpp 会拒载，最危险的是**静默加载然后输出乱码**——换二进制后先跑一句看输出。
4. **`llama-cli` 没有 `-no-cnv`**：单轮用 `--single-turn`。
5. **HF 大文件下载会 SSL 断流**：永远带 `-C -`，断了重跑即可续传。

## 六、开机自启（systemd user unit）

`~/.config/systemd/user/<name>-llama.service` 模板：

```ini
[Unit]
Description=<模型名> local LLM (llama.cpp + ROCm, Radeon RX 7900 GRE)
After=dev-kfd.device
Wants=dev-kfd.device

[Service]
Type=simple
WorkingDirectory=%h/.model/<模型名>
EnvironmentFile=-%h/.config/<name>-llama.env
Environment=LD_LIBRARY_PATH=%h/.model/<模型名>/bin-rocm:/opt/rocm/lib
Environment=HIP_VISIBLE_DEVICES=0
Environment=LLM_CTX=65536
Environment=LLM_PORT=8081
ExecStart=%h/.model/<模型名>/bin-rocm/llama-server \
  -m models/<model>.gguf \
  -ngl 99 -fa on \
  -c ${LLM_CTX} --cache-type-k q4_0 --cache-type-v q4_0 \
  --host 127.0.0.1 --port ${LLM_PORT} --alias local-model
Restart=on-failure
RestartSec=15
TimeoutStartSec=600

[Install]
WantedBy=default.target
```

上下文与端口走环境变量，改配置**不要动单元文件**，写 drop-in 或 env 文件：

```bash
mkdir -p ~/.config/systemd/user/<name>-llama.service.d
printf '[Service]\nEnvironment=LLM_CTX=32768\n' > ~/.config/systemd/user/<name>-llama.service.d/ctx.conf
systemctl --user daemon-reload && systemctl --user restart <name>-llama

systemctl --user status <name>-llama       # 看状态
journalctl --user -u <name>-llama -f       # 看日志
systemctl --user stop <name>-llama         # 腾显存（不会自动重启）
loginctl show-user sx -p Linger            # 必须是 Linger=yes 才能开机自启
```

**开机自启的前提是 linger 打开**（`sudo loginctl enable-linger sx`）——否则用户级服务只在登录后才起。

## 七、接进 DSH 当 provider

本地 llama-server 是 OpenAI 兼容接口，在 profile 的 `llm-pi-ai` 里加一条 provider：

```yaml
llm-pi-ai:
  providers:
    local-llm:
      displayName: <模型名> (local)
      api: openai-completions
      baseURL: http://127.0.0.1:8081/v1
      headers: { Authorization: "Bearer local-no-auth" }   # 见下方坑
      models:
        - id: local-model
          name: <模型名> (local AMD)
          contextWindow: 65536
          maxTokens: 8192
```

- **keyless 本地服务也必须给占位凭据**：pi-ai 的 `openai-completions` 实现强制要求 API key 或 `Authorization` 头，光省掉 `apiKeyEnv` 会在请求时被拒。用 `headers.Authorization` 最省事。
- provider id 用小写连字符（`local-llm`），别用大写/下划线。
- 改完 composition 需要**重启 DSH 才进模型选择器**；改完先确认 composition 能加载，再重启服务。
- 选模型走会话里的模型选择器；不要改 `agent-default-model`（本地小模型比云端主力弱，只适合离线/隐私场景）。

## 八、思考档位（若模型自带）

本地模型思考强度**由模型自带 chat template 定死**，不是自由参数。权威判据是服务端 `/props` 里的 `chat_template`：

```bash
curl -s localhost:8081/props | python3 -c 'import json,sys; print(json.load(sys.stdin)["chat_template"])'
```

模板里 `raise_exception` 那几行就是合法取值集合；**传不认的值会 500**。

### 映射进 DSH

`reasoningEfforts` 的**键**是菜单档位（DSH 认 off/minimal/low/medium/high/xhigh/max），**值**就是发到线上的 `reasoning_effort`；未声明的档位会变成 `null` 而被隐藏，所以菜单里只出现声明过的。

```yaml
      reasoning: medium          # 会话未选档位时的默认，务必显式给
      models:
        - id: local-model
          reasoningEfforts:
            "off": none          # 注意引号：不加会被 YAML 1.1 解析成布尔 false
            low: low
            medium: medium
            xhigh: xhigh
```

- **`off` 的键必须加引号**。`off` 在 YAML 1.1 里是布尔假，不引号会变成键 `false`，档位静默消失。
- **路由级 `reasoning` 一定要显式给**。pi-ai 在「会话没选档位」时会把 `thinkingLevelMap.off` 当 `reasoning_effort` 发出去；配了 `off: none` 却不给默认档，等于**默认静默关闭思考**。
- 无需配 `compat.supportsReasoningEffort`：它对手写路由默认就是 `true`。
- 配错值表现为运行期 500，**改完必须实测一档**。

## 九、排障速查

| 症状 | 先查 |
|---|---|
| HIP 后端没加载、`--list-devices` 空 | `ldd bin-rocm/*.so \| grep 'not found'`，缺库补 `hipblas` |
| 显存不够 / OOM | 降 `-c`（KV 按 18 KiB/token@q4_0 算）、去掉视觉塔、加 `--no-mmproj-offload` 把视觉塔放内存 |
| 速度只有个位数 tok/s | 确认 `-ngl 99` 真的生效（看启动日志）、显存占用是否只有一两 GB（说明没卸载到 GPU） |
| 输出是乱码 | 用错二进制（stock llama.cpp 认不了专用量化）或文件/二进制不配对 |
| 换档位后 500 报错 | 传了模板不认的值，看 `/props` 的 chat_template |
| 模型不思考了 | 检查是否配了 `off: none` 但没给路由级 `reasoning` 默认档 |
| `error: invalid argument` | 参数名对不上，先在 `--help` 里确认 |
