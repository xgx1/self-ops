---
name: scanned-doc-ocr-extraction
description: 扫描型 PDF / 老 .doc 文档提取文本：pymupdf 导出页图 → inspect_image（DSH 原生视觉 OCR）；.doc 用 olefile + utf-16le 提取。处理扫描合同、扫描件、微信收到的旧文档时使用。
---

# 扫描文档文本提取（PDF 图片型 / 老 .doc）

## 适用
- 扫描型 PDF（read 返回 Image pN-img0 而非文本）
- 老 .doc 二进制格式（read 报 not valid UTF-8）
- 微信收到的合同/协议书等

## PDF（图片型）流程
1. 安装：`pip install pymupdf -q -i https://pypi.tuna.tsinghua.edu.cn/simple`（国内必须镜像）
2. 导出页图（直接 130dpi JPEG quality=82 最稳——大图会让视觉调用超时；PIL 需 `pip install pillow`）：
```python
import pymupdf, os
doc = pymupdf.open(pdf_path)
for i, page in enumerate(doc):
    pix = page.get_pixmap(dpi=130)
    pix.pil_save(os.path.join(out, f'p{i+1}.jpg'), quality=82)
```
3. OCR：`xd://mcp__qwen_mm_plugins_core_ocr`（参数 `image_path`，prompt 写"完整提取全部文字，保留条款编号和标点，逐字转录"）
   - **陷阱**：DashScope ocr 间歇性 30s 超时——实测参数：200dpi PNG（3-4MB/页）必超时，100dpi JPEG quality=82（~500KB）才稳（但 500KB 也可能超）——超时换 `xd://inspect_image`（path + question，本机 vision role，稳定）
   - 并行逐页调用，超时页单独重试
4. 中文 OCR 易错：公司名/数字/主语需人工核对原件（例："太崆"vs"太隆"印章、7.2 主语笔误）。OCR 结果必须标注存疑清单（公司名/数字/主语）。公司名/印章可能互相矛盾（正文 vs 盖章），诉讼类文档必须让用户核对

## .doc 老格式流程
```python
import olefile, re
ole = olefile.OleFileIO(p)
data = ole.openstream('WordDocument').read()
text = data.decode('utf-16-le', errors='ignore')
chunks = re.findall(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffefA-Za-z0-9，。、；：（）()：%《》"\'．.\-—·\s]{4,}', text)
```
过滤保留含中文的 chunk 拼接。无 Office/无 WPS/无 LibreOffice 环境可用此纯 Python 法。

## 证据处理配套
- 原始文件先复制归档（勿动微信原件），提取文本存 md 旁注
- OCR 文档标注「正式引用前对照原件核对」
