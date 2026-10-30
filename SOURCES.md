# 素材来源与许可（SOURCES）

本项目的美术素材**不是原创**，来自社区公开的二创项目；代码为本项目自写。

## 动画帧（`Resources/pet/fatfish-*.webp`）

- 原始图集：`gmskywalker/deepseek-fat-fish-codex-pet`（原仓库未提供明确的开源许可；README 声明为非官方、非商业同人桌宠）
  https://github.com/gmskywalker/deepseek-fat-fish-codex-pet
  当前 23 帧直接裁切自 `deepseek-fat-fish/spritesheet.webp`：1536×2288，8 列×11 行，每格 192×208，原生 RGBA 透明背景。
  本机来源为 `../大肥鱼皮肤源码/deepseek-fat-fish-codex-pet-main/deepseek-fat-fish/spritesheet.webp`。
  图集文件 SHA-256：`77a048aef03f310ef33ffd38916c9da3495851a100266dd6bfbdc25502dca6ed`。
- 动画映射采用从零开始的行列坐标，并保留原有帧数与顺序：
  - `idle`：第 0 行，第 0–5 列，6 帧。
  - `hover`：第 4 行，第 0–4 列，5 帧；对应原图集 `jumping` 动作。
  - `working`：第 7 行，第 0–5 列，6 帧；对应原图集 `running` 动作。
  - `success`：第 8 行，第 0–5 列，6 帧；对应原图集 `review` 动作。
- 提取脚本：`scripts/extract-pet-frames.py`（需要 Pillow）。脚本直接裁切原图集并保存为 192×208 的无损 RGBA WebP，逐像素校验 RGB 与 alpha；保留半透明边缘及白色头饰、裙摆、袜子，不进行抠白、缩放、重绘或角色替换。运行提取时必须指定外部备份目录，已有备份不会被覆盖；`--verify-only` 可只验证当前 23 帧。
- 旧版拆帧与透明化成品曾取自：`roseion/dsh-dayu-fish-skin`（MIT）
  https://github.com/roseion/dsh-dayu-fish-skin
  旧素材来自 `fish/fatfish-{idle,hover,working,success}-N.webp`。其 GIF 预览底图含已烧入的棋盘格，透明化同时误删了角色的部分白色区域。2026-10-30 已用上述原生透明图集帧替换，原有文件名、四组状态及 6/5/6/6 帧数保持一致。

## 鲸鱼娘立绘（`Resources/pet/whale-*.webp`）

- `YunYueSama/codex-deepseek-pet`：鲸鱼女仆透明 PNG（12 姿势 + 三视图）
  https://github.com/YunYueSama/codex-deepseek-pet
- `1190fasheqi/dafeiyu-pet`（MIT）：鲸鱼娘·大肥鱼透明桌宠
  https://github.com/1190fasheqi/dafeiyu-pet
- 经 `roseion/dsh-dayu-fish-skin` 处理成透明 WebP 后复用（`whale-happy.webp` 用作面板头像）。

## 角色设定

「小鲸 / DeepSeek 酱」角色设定图作者：@田中智（白米饭控 / 爱金币 /「我不是吃白饭的！」）。设定图与二创图版权归原作者，本项目仅作个人桌面工具装饰。

## 使用限制

- 仅限个人学习 / 自用；请勿商用、二次分发图包或冒充官方。
- 若你是权利人并希望移除素材，删掉 `Resources/pet/` 下对应文件即可，程序只按文件名引用。


## 走路帧（`Resources/pet/fatfish-walk-0..7.webp`）

- 取自 `boyl/deepseek-blue-whale` 的 Codex v2 图集（`spritesheet.webp`，1536×2288，8 列 × 11 行，每格 192×208）第 2 行（row 1）的 8 帧走路循环，原图朝左，向右走时由程序水平镜像。
  https://github.com/boyl/deepseek-blue-whale
- 其余待机 / 悬停 / 写作 / 干饭四组帧见 `scripts/extract-pet-frames.py` 的提取映射（idle=row 0、hover=row 4、working=row 7、success=row 8）。

## 参考项目（源码留档）

全部源码已下载到 `../大肥鱼皮肤源码/`，索引见该目录 `INDEX.md`。
