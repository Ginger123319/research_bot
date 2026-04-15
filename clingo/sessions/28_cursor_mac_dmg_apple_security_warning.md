# 我刚刚打开一个自己开发的 .dmg 提示我 Aplle 无法验证 "fit-curve" 是否包含可能危害Mac安全或泄...
_Exported on 2026/3/13 at GMT+8 18:08:15 from Cursor (transcript)_

---

**User**

我刚刚打开一个自己开发的 .dmg 提示我
Aplle 无法验证 "fit-curve" 是否包含可能危害Mac安全或泄漏隐私的恶意软件。

---

**Cursor**

这是 macOS **Gatekeeper** 的安全提示，针对未经 Apple 公证（Notarization）或代码签名的应用程序会显示此警告。这是正常现象，尤其是自己开发的应用。

## 解决方法

### 方法一：在系统设置中允许（推荐）

1. 尝试打开 .dmg，出现警告后点击**取消**
2. 打开 **系统设置** → **隐私与安全性**
3. 在页面下方会看到类似 **"fit-curve" 已被阻止** 的提示
4. 点击右侧的 **"仍要打开"** 按钮，输入密码确认即可

### 方法二：右键打开

1. 在 Finder 中找到 .dmg 文件
2. **右键点击**（或 Control + 点击）
3. 选择 **"打开"**
4. 在弹出的对话框中点击 **"打开"**

### 方法三：终端命令移除隔离属性

```bash
xattr -dr com.apple.quarantine /path/to/fit-curve.dmg
```

然后正常双击打开即可。

---

## 根本解决方案（如果要分发给他人）

如果你希望其他用户不再看到此警告，需要：

1. **代码签名**：使用 Apple Developer 证书对应用签名
2. **公证（Notarization）**：将应用提交给 Apple 公证服务审核

```bash
# 签名
codesign --deep --force --sign "Developer ID Application: 你的名字" fit-curve.app

# 公证
xcrun notarytool submit fit-curve.dmg --apple-id 你的AppleID --team-id 你的TeamID --wait
```

这需要 **Apple Developer 账号**（$99/年）。如果只是自用或小范围分发，方法一或二就够了。

The user is asking about a macOS security warning when opening a .dmg file they developed themselves. This is a common macOS Gatekeeper issue. Let me explain how to bypass this warning.

---
