# 工具环境与复现

Windows 工程包使用 `python tools/fetch_windows_template.py` 获取经版本与 SHA-256 核对的官方 release 模板，再执行 `./tools/build_windows.ps1 -Godot <Godot-console.exe>`。构建器包含全量回归、导出、实际 PCK 内容与 exe 启动检查，生成附日志和校验值的 ZIP；完整复现与人工验收边界见 [WINDOWS_DELIVERY](../docs/engineering/WINDOWS_DELIVERY.md)。构建工具不依赖素材处理的第三方 Python 包。

游戏运行不依赖 Python。Godot 使用仓库标注的 4.7.2 Standard，正式玩法参数来自 `data/*.tres` 与类型化技能目录；技能栏完整说明直接读取 SkillDefinition，短提示由射程、形状和段数生成，不再维护第二份招式数字表。修改自然语言说明仍须与所属目录字段一同审阅。

素材处理环境验证于 Windows / CPython 3.14.4。三个直接依赖精确固定在 `requirements.txt`；OpenCV 只使用无 GUI 的 headless 包，与 [官方 PyPI 包说明](https://pypi.org/project/opencv-python-headless/) 一致。

```powershell
python -m venv .godot/sprite-venv
.godot/sprite-venv/Scripts/python.exe -m pip install --only-binary=:all: -r tools/requirements.txt
.godot/sprite-venv/Scripts/python.exe tools/verify_sprite_pipeline.py
```

验证器将现有瑟弗林原图复制到项目缓存中的独立目录，调用真实命令行两次，检查立绘透明通道、归一高度、头像尺寸及两次 PNG SHA-256 相等；不会覆写已入库素材。退出时只清理本次创建并核对过的缓存子目录。

处理新素材可显式指定输入输出；不提供参数时保留原有批处理行为：

```powershell
.godot/sprite-venv/Scripts/python.exe tools/process_sprites.py --input .godot/my-raw --output .godot/my-processed
```

`generate_pause_audio.py` 使用 Python 标准库生成现有音效，不需要额外第三方包。检查、构建工具的日志和生成物放入 `.godot` 或 `build`，不混入源码提交。
