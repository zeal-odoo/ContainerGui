# Quickstart Validation: Material Design 3 界面视觉升级

## 1. 测试先行

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter Material3AssetTests
```

预期：实现前因缺少 Material 3 语义令牌、组件状态、深色/减少动态效果与无远程依赖契约而失败；实现后全部通过。

## 2. 完整回归

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
node --test Tests/Frontend/*.mjs
git diff --check
```

预期：全部现有容器、镜像、SSH、Odoo、重启、容量、API 和前端行为测试继续通过。

## 3. 运行服务

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build
.build/arm64-apple-macosx/debug/ContainerGUI
```

打开 `http://127.0.0.1:8787/#main`。只重启 GUI 服务，不启动、停止、重启或删除真实容器。

## 4. 浏览器可见验收

在扩展宽度验证：

1. 顶部显示 GUI v2.11.0，页面采用语义表面和紫蓝主色，但现有入口、文案和布局任务不变。
2. 统计卡、容器列表、详情、本机镜像和远程搜索层级清楚。
3. 主要、次要、危险与禁用操作可辨认；键盘焦点可见。
4. 本机镜像箭头向右时收起、向下时展开。
5. 创建容器、拉取镜像与确认弹窗的表面、字段和操作区一致；不提交真实变更。

在紧凑宽度验证：

1. 主列表和详情变为单列，页面无整体横向溢出。
2. 表格只在自身区域滚动，操作按钮与表单字段不越界。

在浅色和深色主题各验证一次：所有正文、状态、轮廓、焦点和错误均可读；浏览器控制台无新增 warning/error。

## 5. 只读运行态回读

```bash
curl -sS http://127.0.0.1:8787/api/v1
curl -sS http://127.0.0.1:8787/app.css
```

预期：API 返回应用版本 2.11.0；CSS 使用本机静态资源并包含浅色/深色 Material 3 令牌。不得通过浏览器点击任何会写入真实容器状态的提交按钮。
