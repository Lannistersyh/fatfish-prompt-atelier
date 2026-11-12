# 桌宠运行时补丁（可选）

`大肥鱼.app` 需要桌宠运行时：

```
~/Library/Application Support/dafeiyu1080/runtime
```

来源为 MIT 许可的 `dsh-pet-standalone`（Copyright (c) 2026 Merzlin）。
本目录只保存**新加的文件**；其余为对上游文件的就地小改，改动点见 `docs/2in1.md`。

## 应用

```bash
RT="$HOME/Library/Application Support/dafeiyu1080/runtime"
cp pet/workshop_bridge.py "$RT/pet/workshop_bridge.py"
```

然后按 `docs/2in1.md` 的 5 个补丁点改 `window.py`、`context_menus/registry.py`、
`menu_templates/modern-default-v1.json`、`overlay_shell.py`、`app.py`。

## 兼容性

补丁基于 2026-10/11 的运行时版本（106 段 1080P 素材）。上游文件若升级，
行号会变，但改动点（函数名 / JSON 键 / 通知名）保持稳定，按名字定位即可。
