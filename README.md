# RawBridge

RawBridge 是一个独立的原生 iPhone / iPad 应用，用于从 Apple 照片图库中取出相机原片。比如在一条 JPEG + NEF 照片记录上选取 **RAW**，即可把其中的 NEF 按原名存到“文件”。选取 **RAW + JPEG** 会分别输出两个文件。图库网格使用系统缩略图，导出直接读取所选的底层资源。

## 打开工程

使用 Xcode 27.2 打开 `RawBridge.xcodeproj`，选择 **RawBridge** scheme 和 iPhone 或 iPad，运行即可。最低部署版本为 iOS / iPadOS 17.0。使用个人设备时，在应用 target 的 Signing & Capabilities 中选择自己的开发团队。工程已包含共享 scheme，应用无外部包依赖。修改工程结构时，可使用 XcodeGen 2.45.3 和 `project.yml` 重新生成工程。

## 提取照片

1. 首次启动选择允许访问的照片，或授予完整图库访问。在有限访问模式下，图库顶部可管理所选照片。
2. 打开照片详情。资源清单展示 PhotoKit 报告的文件名、资源角色、UTI 和可知的文件大小。同一条记录中出现 JPEG 和 RAW 两种原始资源时，可以切换预览。编辑产生的衍生文件、Live Photo 视频和调整数据只出现在清单中。
3. 点 **导出**，选择 **RAW**、**JPEG** 或 **RAW + JPEG**。双格式模式只处理同时具备两种原始资源的照片，界面显示不满足条件的照片数量。HEIF + RAW 资产可提取其中的 RAW。
4. **存储到“文件”** 会打开系统目录选择器。可选位置由设备决定，包括“我的 iPad / iPhone”、iCloud Drive 和已挂载的外接盘。**准备分享文件** 完成后点 **分享**，从系统面板选择接收应用。
5. 从图库点 **选择** 可批量操作。**全选** 只选择当前筛选结果。导出中显示当前文件、iCloud 下载进度、完成数量、失败原因。重试处理当前操作中尚未完成的文件。重名策略支持保留两份（在扩展名前加序号）或报告冲突。
6. 在 **设置 → 校验文件完整性** 分别选取相机卡上的原片和实际保存的文件，对比两者的字节数和 SHA-256。分享面板准备好文件后，接收方如何保存取决于对应应用。要验证最终结果，请选择接收方实际保存的文件。

## 资源识别与兼容

- 扫描以照片资产为入口。应用对每项调用 `PHAssetResource.assetResources(for:)`，依据 `.photo` / `.alternatePhoto`、UTI 及其一致性决定可导出的原始资源。JPEG 和 RAW 都可能出现在其中任一角色。
- 首选 `UTType.rawImage`。当类型信息宽泛或未注册时，允许 NEF、NRW、CR2、CR3、ARW、RAF、RW2、DNG、RWL、ORF、PEF 后缀参与识别。明确的 JPEG、HEIF 和 PNG 类型优先于文件名。依赖后缀识别的 RAW 还需通过文件头检查。扩展名或平台可解码机型列表均不足以证明文件无损。
- DNG 既可来自 Apple，也可来自其他厂商。详情页使用 ImageIO 读取原始资源的 TIFF 和 DNG。遇到明确命名的 Apple ProRAW 配置，或 Apple 线性 RAW、iPhone 相机标识及 Apple 嵌入色彩配置的组合时，标记 Apple ProRAW。未知的 DNG 仍可作为 RAW 提取。相机品牌筛选先使用厂商特有格式。对 JPEG、DNG 等通用格式，可以在筛选菜单点“读取本地照片的相机品牌”，从本地可得的元数据补充索引。
- Core Image 独立负责 RAW 预览。设备无法解码时，详情页给出提示，导出仍使用 PhotoKit 的原始字节。图库缩略图可能显示一张系统渲染的照片。
- `PHAssetResource` 和 `writeData` 从 iOS 9 可用，限定授权和 `UTType.rawImage` 从 iOS 14 可用，`CIRAWFilter` 从 iOS 15 可用。本工程使用 iOS 17 的 SwiftUI 组件。iOS 26 起使用资源的 `contentType`，iOS 27 起使用 `filename` 及可选的公开 `dataSize`，旧版本使用 `originalFilename` 与 `uniformTypeIdentifier`。未知大小在读到文件后按实际字节数显示。
- 只有当 Photos 在用户授权的资产上提供原始资源时，RawBridge 才能提取。若系统导入时只保存 JPEG，应用会显示可用资源。

[Apple 的照片资源模型](https://developer.apple.com/documentation/photos/phassetresource) · [PhotoKit 原始字节写出](https://developer.apple.com/documentation/photos/phassetresourcemanager/writedata(for:tofile:options:completionhandler:)) · [RAW UTI](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/rawimage) · [iCloud 下载选项](https://developer.apple.com/documentation/photos/phassetresourcerequestoptions/isnetworkaccessallowed) · [Apple ProRAW 与 DNG](https://developer.apple.com/videos/play/wwdc2021/10160/)

## 文件与隐私

本地单张导出优先使用 PhotoKit 的异步 `writeData`。批量导出和允许 iCloud 下载的任务使用可取消的 `requestData`，按块写入独立临时目录，同一窗口依次处理。下载默认关闭。对于一个需要下载的资源，Photos 的官方错误会提示开启网络访问。iCloud 下载进度仅在系统提供时显示。

写入目标目录时使用 security-scoped URL 和 `NSFileCoordinator`。先写临时文件，按 1 MiB 分块核对字节数与 SHA-256，再发布为最终文件名。失败或取消时清理本次临时输出。已完成的文件可保留。取消本地单张 `writeData` 时，系统可先完成当前异步写入，应用会在发布前检查取消状态。分享会占用临时存储，直到关闭导出面板。

应用使用 PhotoKit 的读取授权级别 `.readWrite` 获取可见资产。应用 target 仅读取图库。创建配对资产的代码只在模拟器测试 target 内。应用不包含账户、遥测、广告 SDK 或后端，不持久化 EXIF 与照片位置。设置保存在设备本地。文件提供方和分享目的地由用户选择。英文与简体中文跟随系统的单个 App 语言设置。

## 测试

在 Xcode 中按 **⌘U** 运行单元测试和界面测试。真实 PhotoKit 样本集成用例要求在模拟器中安装指定样本，未安装时 XCTest 明确记为跳过。

在仓库根目录运行以下命令，可向指定模拟器安装公开 Nikon NEF 测试素材，授权**模拟器里的 RawBridge** 访问其照片图库并执行完整测试。脚本留下测试资产供手动查看，请选用开发用模拟器。网络仅用于首次取得测试样本。

```sh
xcrun simctl list devices available
./Scripts/test-nikon-pair.sh <模拟器UDID>
```

可选的 Apple DNG 用例使用 [raw.pixls.us 的 iPhone 12 Pro 样本](https://raw.pixls.us/getfile.php/4264/nice/Apple%20-%20iPhone%2012%20Pro%20-%208bit%20%284%3A3%29.DNG)。将下载文件的本地路径作为脚本的第二个参数，即可一并测试。

该脚本验证固定样本 SHA-256，再用 macOS 的 sips 为其生成测试 JPEG。测试通过 PhotoKit 创建设定的配对关系，随后用产品代码扫描、提取和保存。源码仓库和应用包都不包含样本照片。USB 导入的资产结构、iCloud 仅云端资源与外接盘行为请按实机步骤独立验证。[公开 NEF 来源](https://github.com/letmaik/rawpy/tree/main/test)

[本次构建与测试记录](docs/validation.md) · [实机测试说明](docs/device-tests.md) · [MIT 许可](LICENSE)
