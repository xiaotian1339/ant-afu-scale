<div align="center">

<img src="Scale/Assets.xcassets/AppIcon.appiconset/Scale_1024.png" width="128" alt="Scale App Icon" />

# Scale · 蚂蚁阿福体脂秤

一个原生 iOS App，通过蓝牙连接蚂蚁阿福体脂秤，读取体重与阻抗，本地估算身体成分，并同步到 Apple「健康」。

</div>

## 简介

Scale 是用 SwiftUI 写的 iOS 体脂秤 App。手机作为蓝牙中心设备直接与体脂秤通信，无需依赖原厂 App 或云端：

- 自动扫描并连接沃莱系列体脂秤（服务 UUID `FFB0`），并记住上次连过的秤下次直连。
- 连接后向秤下发用户资料（身高 / 年龄 / 性别），触发它做阻抗测量。
- 解析秤的 "Scale27" 蓝牙协议（体重包 / 阻抗包），实时显示体重、稳定后锁定读数。
- 基于阻抗 + 用户资料，本地用 BIA 公式估算体脂率、BMI、水分率、肌肉率、基础代谢、去脂体重。
- 测量完成后自动把体重、体脂率、BMI、去脂体重写入 Apple「健康」App。

> ⚠️ 体脂等身体成分为使用体脂秤提供的原始阻值以本地公式估算，与原厂 App 的计算公式不完全一致，仅供参考（反正都差不多准）。

## 使用方法

本项目未上架 App Store，需要下载打包好的 IPA 后自行安装到 iPhone。整体流程：**下载 IPA → 签名 → 安装 → 首次运行授权**。

### 0. 自动构建与发布无签名 IPA

`.github/workflows/build-unsigned-ipa.yml` 会在推送到 `main`、推送版本标签（如 `v1.0.0`）或在 `main` 手动运行时构建，并自动创建对应版本的 GitHub Release，上传 `Scale-v1.0.0-unsigned.ipa`。Pull Request 只测试、构建和上传 Actions Artifact，不发布 Release。

- `main` 的版本取自 Xcode 项目的 `MARKETING_VERSION`；发布新版本前同时更新 Debug / Release 的版本号。
- 标签必须为 `v主版本.次版本.修订版本`，标签构建会将该版本写入 IPA。
- 已发布的版本不会被覆盖；同版本后续构建仍可从 Actions Artifacts 下载。
- 构建关闭代码签名，不需要 Apple 证书、Development Team 或签名密钥。IPA 安装前仍需自行签名。

### 1. 下载 IPA

从[本仓库 Releases](https://github.com/xiaotian1339/ant-afu-scale/releases)下载无签名安装包，或从 Actions 的 `Scale-unsigned-ipa` Artifact 下载。签名方式如下。

### 2A. 自签名（免费，证书 7 天有效）

用一个普通 Apple ID（免费开发者账号）给 IPA 签名。证书只有 **7 天有效期**，到期后 App 会打不开，需要重新签一次；期间不要删除签名工具。

需要：一台电脑（Windows / macOS）+ 数据线 + 一个 Apple ID。

以 **Sideloadly**（[sideloadly.io](https://sideloadly.io)，Win/Mac 都有）为例：

1. 电脑装好 Sideloadly，用数据线连上 iPhone，手机上点「信任此电脑」。
2. 打开 Sideloadly，把下载好的 `Scale.v0.1.ipa` 拖进去。
3. 在 Apple account 处填你的 Apple ID，点 **Start**，按提示输入密码。
4. 等进度条走完，App 就装到手机上了。

> AltStore、Feather、爱思助手等工具同理

### 2B. 闲鱼代签（几块钱，签名约 1 年有效）

原理是让卖家用他们的**99 美元/年的付费开发者账号**把你的设备加进去，再签名给你，有效期约 1 年。在闲鱼搜「**iOS 开发者签名 / 代签名 / p12 签名**」，几块钱一个。

流程通常是：

1. 提供你 iPhone 的 **UDID**（设备唯一标识）。
   - 手机 Safari 打开卖家给的 UDID 获取链接，安装一个描述文件即可读出。
2. 卖家给你签名的证书（p12）和描述文件（mobileprovision）
3. 用 [**zsign**](zhlynn/zsign) 之类支持改 Bundle ID 的工具重签名，**必须把 Bundle ID 改成描述文件里授权的那个**，例如：

   ```bash
   zsign -k cert.p12 -p 密码 -m profile.mobileprovision -b 描述文件里的BundleID -o Scale-signed.ipa Scale.v0.1.ipa
   ```

4. 签好的 IPA 用爱思助手 / Sideloadly 装上

> ⚠️ **别直接用爱思助手的「证书签名」功能**：它不改 Bundle ID，签完打开会报 `Missing com.apple.developer.healthkit entitlement`，数据无法写入苹果健康。
>
> 原因：用了新证书却没改 Bundle ID，iOS 会把**整份 entitlements 判为无效**，而不是只丢某一条，所以明明签进去的 HealthKit 也会报 missing。只有把 Bundle ID 改成描述文件授权的那个，权限才会生效。

> 也有企业签等更便宜的方案，但企业签容易被苹果吊销（掉签），装完随时可能打不开；追求稳定优先选个人开发者账号代签。

### 3. 首次运行

装好后第一次打开，按下面处理：

1. **信任开发者**：若提示「未受信任的开发者」，去 *设置 → 通用 → VPN与设备管理*，点开对应描述文件选择「信任」。
2. **打开开发者模式**（仅自签名需要，iOS 16+）：*设置 → 隐私与安全性 → 开发者模式*，打开后重启手机。
3. **授予权限**：首次进入会依次请求
   - **蓝牙**权限——用来连接体脂秤，必须允许；
   - **健康**写入权限——用来把测量结果同步到「健康」App，按需允许（不想同步可在 [我的资料](Scale/UserProfile.swift) 里关掉「测量后自动写入健康」开关）。如果不小心按错了可以在健康App里重新授予；若 App 提示签名缺少 HealthKit 能力，请按上面的重签说明检查 Bundle ID 和描述文件
4. **填写资料**：点右上角头像图标，填身高 / 年龄 / 性别（体脂估算需要），点保存。
5. **开始测量**：确保手机蓝牙已开、体脂秤有电，点「开始测量」，光脚站上秤保持不动，等读数稳定即可。

## 运行截图

| 测量结果 | 我的资料 |
| :---: | :---: |
| <img src="readme.assets/IMG_2596.PNG" width="300" alt="测量结果" /> | <img src="readme.assets/IMG_2595.PNG" width="300" alt="我的资料" /> |

## 项目结构

| 文件 | 作用 |
| --- | --- |
| [ContentView.swift](Scale/ContentView.swift) | 主界面：测量状态、结果卡片、资料设置页 |
| [BluetoothManager.swift](Scale/BluetoothManager.swift) | CoreBluetooth：扫描 / 连接 / 订阅通知 / 下发资料 / 稳定判定 |
| [Scale27.swift](Scale/Scale27.swift) | 沃莱 "Scale27" 蓝牙协议的编解码 |
| [BodyComposition.swift](Scale/BodyComposition.swift) | 阻抗 + 资料 → 身体成分的 BIA 估算公式 |
| [HealthKitManager.swift](Scale/HealthKitManager.swift) | 把测量结果写入 Apple「健康」 |
| [UserProfile.swift](Scale/UserProfile.swift) | 身高 / 年龄 / 性别，存本地 UserDefaults |

## 参考项目：ant-afu-welland-scale

本项目的蓝牙协议与估算逻辑参考了 [`ant-afu-welland-scale`](https://github.com/Mzdyl/ant-afu-welland-scale) —— 一个用 Python 写的 macOS 命令行读秤工具。Scale 把它的核心算法移植成了 Swift，具体借鉴的部分：

- **"Scale27" 蓝牙协议解析**：[Scale27.swift](Scale/Scale27.swift) 移植自其 `protocol.py`，包括 20 字节数据包的包头 / 包类型判定、体重编码的取整与刻度换算（`gunit`）、阻抗归一化，以及下发时间 + 用户资料（`encode_time_and_user_info_27`）以触发体脂测量的逻辑。
- **身体成分估算公式**：[BodyComposition.swift](Scale/BodyComposition.swift) 的 BIA 公式源自其使用的 `ha-miscale2` 算法，用体重、阻抗、身高、年龄、性别估算体脂率、水分、骨量、肌肉率等。
  

区别在于：`ant-afu-welland-scale` 是 macOS 上跑的 Python CLI，而 Scale 是 iOS 原生 App（靠 CoreBluetooth + SwiftUI），并额外接入了 Apple「健康」。参考项目自身的用法请见其仓库：<https://github.com/Mzdyl/ant-afu-welland-scale>。

## 新增功能与开发验证

功能移植自 [ShawnRn/ant-afu-scale](https://github.com/ShawnRn/ant-afu-scale) 的 `5479f0a`：本地历史记录、按自然日取最新一次测量的趋势图、更多身体指标与评估、自定义头像、从 Apple「健康」读取身体资料，以及用户授权文件夹中的 iCloud 云盘同步。身体成分仍为估算值；本次移植也采用了对方的身体成分公式，结果可能与旧版不同。

应用最低支持版本保持 **iOS 16.0**。未引入对方的个人 Development Team、签名脚本、iOS 27 部署要求或个人 Xcode 设置。文件夹同步依赖系统文件选择器授权，不要求应用自有 iCloud 容器；解除绑定后停止后续同步，已开始的文件操作可能仍会完成。同步按记录 UUID 合并；删除只影响本地记录，云端已有记录可能在下一次同步时重新导入，清理云端备份需自行处理。

在 macOS / Xcode 上运行核心回归检查：

```bash
swiftc -swift-version 5 Scale/UserProfile.swift Scale/Scale27.swift Scale/BodyComposition.swift Tests/CoreTests.swift -o /tmp/scale-core-tests
/tmp/scale-core-tests
```

Actions 会执行这些检查，并以 iOS 16 部署目标进行无签名 Release 构建。蓝牙通信、iCloud 文件授权、导航交互和 HealthKit 同步需在真机验证。Linux 无法完成 iOS 构建与真机验证。

## v1.0.1 修复与隐私审查

- 文件夹选择改用 `UIDocumentPickerViewController` 的原生打开模式与代理回调，处理空文件夹选择并在关闭选择器前保存访问书签；绑定失败会显示具体原因。
- 绑定及每次同步都会检查目录来源，仅支持应用自己的本地 Documents 目录或系统标记的 iCloud 目录，拒绝第三方文件服务、无法验证来源的目录与符号链接。旧版已绑定的第三方目录也会停止同步；请重新选择 iCloud 云盘文件夹。
- 拷贝测量数据仅限当前设备，并在一分钟后过期，不进入通用剪贴板。
- HealthKit 保留体重、BMI、体脂率、去脂体重四项；骨量、体水分量、肌肉量没有公开的对应类型，BMR 估算也不会作为累计基础能量消耗写入。
- 详细数据流向及系统隐私边界见 [隐私说明](PRIVACY.md)。目录选择和持久授权仍需 iOS 26 真机验证。
