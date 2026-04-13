# 开发手册

## 环境要求

| 工具 | 版本要求 | 用途 |
|------|----------|------|
| Flutter SDK | **3.38.5** (stable channel) | 跨平台框架 |
| Dart SDK | **^3.10.4** | 随 Flutter 安装 |
| Visual Studio | 2022 + C++ 桌面开发 | Windows 桌面编译 |
| Android Studio | 最新版 + Android SDK | Android 编译 |
| JDK | **17** (Temurin) | Android 构建 |

---

## 环境搭建

### 1. 安装 Flutter SDK

从 [Flutter 官网](https://docs.flutter.dev/get-started/install/windows) 下载 Windows 版本。

[](https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.38.5-stable.zip)

1. 解压到目标目录（如 `C:\flutter`）
2. 将 `C:\flutter\bin` 添加到系统 PATH 环境变量
3. 验证安装：
   ```bash
   flutter --version
   flutter doctor
   ```

### 2. 启用 Windows 桌面支持

```bash
flutter config --enable-windows-desktop
```
[](https://aka.ms/vs/17/release/vs_Community.exe)

### 3. 安装 Visual Studio 2022

下载地址：https://visualstudio.microsoft.com/

安装时选择 **"使用 C++ 的桌面开发"** 工作负载。这是编译 Windows 应用的必需依赖。

### 4. 安装 Android Studio

下载地址：https://developer.android.com/studio

安装完成后：
1. 打开 Android Studio，进入 SDK Manager
2. 安装 Android SDK (API 33+)
3. 安装 Android SDK Command-line Tools
4. 配置环境变量：
   - `ANDROID_HOME` = `C:\Users\<用户名>\AppData\Local\Android\Sdk`
   - 将 `%ANDROID_HOME%\platform-tools` 添加到 PATH

### 5. 安装 JDK 17

推荐使用 Temurin (Eclipse Adoptium)：
https://adoptium.net/

配置环境变量：
- `JAVA_HOME` = JDK 安装路径
- 将 `%JAVA_HOME%\bin` 添加到 PATH

### 6. 安装 Inno Setup（可选）

用于打包 Windows 安装程序：

```powershell
choco install innosetup -y
```

或从 https://jrsoftware.org/isdl.php 下载安装。

---

## 编译项目

### 获取依赖

```bash
cd memos_flutter_app
flutter pub get
```

### 编译 Windows 应用

```bash
flutter build windows
```

输出位置：`build/windows/x64/runner/Release/`

### 编译 Android APK

```bash
flutter build apk --release
```

输出位置：`build/app/outputs/flutter-apk/`

### 编译 Android App Bundle (AAB)

```bash
flutter build appbundle --release
```

输出位置：`build/app/outputs/bundle/release/`

---

## 调试

### VS Code 调试（推荐）

确保已安装 Flutter 和 Dart 插件，然后：

```bash
cd memos_flutter_app
flutter run -d windows
```

或在 VS Code 中：
- 打开 `memos_flutter_app` 文件夹
- 按 `F5` 或点击 "Run and Debug"
- 选择 Windows 设备

### 命令行调试

```bash
cd memos_flutter_app

# 检查环境
flutter doctor

# 获取依赖
flutter pub get

# 运行调试版本
flutter run -d windows
```

### Android Studio / IntelliJ IDEA

- 打开项目，点击 Run 按钮
- 选择 Windows 设备

### 常用调试快捷键

| 操作 | 快捷键 |
|------|--------|
| 热重载 | `r` |
| 热重启 | `R` |
| 打开 DevTools | `d` |
| 退出 | `q` |

---

## 验证环境

运行以下命令检查环境配置：

```bash
flutter doctor -v
```

预期输出应包含：
- [x] Flutter SDK
- [x] Visual Studio (Windows)
- [x] Android SDK / Android Studio
- [x] Java JDK

---

## 项目结构

```
memoflow/
├── memos_flutter_app/        # Flutter 项目主目录
│   ├── lib/                  # Dart 源代码
│   ├── android/              # Android 平台配置
│   ├── windows/              # Windows 平台配置
│   ├── assets/               # 静态资源
│   └── pubspec.yaml          # 项目依赖配置
├── docs/                     # 文档和截图
└── .github/                  # GitHub Actions 工作流
```

---

## 常见问题

### Flutter 命令找不到

确保 Flutter 的 `bin` 目录已添加到系统 PATH。

### Windows 编译失败

1. 确认已安装 Visual Studio 2022
2. 确认已安装 "使用 C++ 的桌面开发" 工作负载
3. 运行 `flutter doctor` 检查问题

### Android 编译失败

1. 确认 ANDROID_HOME 环境变量已设置
2. 确认 JDK 17 已安装且 JAVA_HOME 已配置
3. 运行 `flutter doctor --android-licenses` 接受许可

### 依赖下载缓慢

配置 Flutter 中国镜像（如需要）：

```powershell
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
```
# Git Fork 项目同步上游 + 本地开发标准工作流
适用场景：Fork 他人项目 → 本地开发自定义功能 → 同步原作者最新提交 → 不冲突、不丢代码

---

## 一、初始配置（仅执行一次）
### 1. 查看当前远程仓库
```bash
git remote -v
```
- `origin`：你自己 Fork 后的仓库（可 push）

### 2. 添加原作者上游仓库（upstream）
```bash
git remote add upstream https://github.com/原作者用户名/原项目名.git
```

### 3. 确认配置结果
```bash
git remote -v
```
正常输出：
- `origin`：你的 Fork 仓库
- `upstream`：原作者项目（仅拉取，不可 push）

---

## 二、核心原则
1. **`main`/`master` 分支只用于同步上游代码，永远不直接开发**
2. **所有自定义功能必须在独立分支上开发**
3. 同步上游更新不会覆盖你的开发分支代码

---

## 三、日常开发完整流程
### 1. 同步原作者最新代码到本地 main 分支
```bash
# 拉取上游所有更新
git fetch upstream

# 切换到本地主分支
git checkout main

# 合并上游主分支到本地
git merge upstream/main
```

### 2. 基于最新 main 新建功能分支
```bash
git checkout -b my-feature
```

### 3. 开发、提交代码
```bash
git add .
git commit -m "feat: 实现 xxx 功能"
```

### 4. 推送到自己的 GitHub 仓库
```bash
git push origin my-feature
```

---

## 四、原作者更新后，同步到你的功能分支
```bash
# 1. 更新本地 main 为上游最新
git checkout main
git fetch upstream
git merge upstream/main

# 2. 切回自己的开发分支
git checkout my-feature

# 3. 合并最新主分支代码
git merge main
```
有冲突则解决冲突后重新提交。

---

## 五、常用命令速查
- 查看远程地址：`git remote -v`
- 拉取上游更新：`git fetch upstream`
- 同步主分支：`git merge upstream/main`
- 新建功能分支：`git checkout -b 分支名`
- 推送到自己仓库：`git push origin 分支名`

---

## 六、结构示意
```
原作者仓库 (upstream)
        ↑
git fetch upstream + merge
        ↓
你的 GitHub 仓库 (origin/main)
        ↑
git pull
        ↓
本地 main（干净、仅同步）
        ↑
git checkout -b
        ↓
本地功能分支（开发自定义代码）
```
