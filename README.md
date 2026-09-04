# 积胜 · Jisheng — Macau Poker Session Tracker / 澳门德州扑克记账

> 积小胜为大胜 — small wins add up to big ones.
> Built with Flutter · Data stays 100% on your device · by VicQIAN

积胜是一款为现场德州扑克玩家设计的牌局记账 App，适合澳门（港币/人民币）现金局。无账号、无注册、无云端——所有数据只存在你自己手机的 SQLite 里。

Jisheng is a poker session tracker for live cash-game players, built around Macau games (HKD/CNY settlement). No account, no registration, no cloud — every record lives only in a local SQLite database on your own phone.

---

## 中文说明

### 功能特性

**记账**
- 记账时间默认取当前，支持手动修改，方便事后补录
- 对局时长支持小数小时（如 3.5 = 3.5 小时）
- 场地预设澳门主流赌场，支持自定义新增
- 港币/人民币双币种，按汇率自动换算显示
- 常用盲注档位下拉选择，支持手动输入
- 盈利绿色、亏损红色，一目了然；备注单行选填

**账单**
- 按「行程」分组展示（可拖拽分界线划分行程），顶部一键封存行程
- 时间范围过滤：全部 / 本月 / 今年 / 近 7 天 / 近 30 天 / 自定义日期 / 按行程多选
- 每张卡片同时显示 HKD 与 CNY 盈亏，底部实时汇总

**统计**
- 净盈亏总览、单场极值、各场地盈亏分布

**波动分析**（bb 口径）
- 累计盈亏曲线 + EV 理论线 + 95%/70% 置信区间带
- 当前回撤、下风概率（蒙特卡洛模拟，固定种子可复现）
- 回答一个扑克玩家最关心的问题：「我的下风期，正常吗？」

**其他**
- 上桌计时：打卡 / 收工，时长自动带入记账
- 兑换记录：港币取现 / 结汇流水
- Excel 导入导出：完整往返备份（含行程还原），换机无忧
- 汇率自动获取（多个公共 API 轮换）并自动保存

### 隐私

- 所有记账数据 100% 存储于手机本地 SQLite，**不上传、不收集、无统计、无广告 SDK**
- App 仅申请 `INTERNET` 权限，且只在「设置页自动获取汇率」时联网（调用公开汇率 API，不传出任何个人数据）；其余功能完全离线可用
- 不申请存储、通讯录、定位等任何敏感权限

### 技术栈

- Flutter（CI 使用 3.19.0 stable，SDK 要求 Dart >=3.0）
- sqflite（SQLite）· Provider（状态管理）· excel（导入导出）· share_plus / file_picker
- 无后端、无账号体系；图表自绘 CustomPainter，无第三方图表依赖

### 构建

```bash
flutter pub get
flutter run              # 调试运行
flutter build apk --release   # 出包
```

> 注：`--release` 默认使用 debug 签名（适合个人侧载）。若要正式分发，请在 `android/app/build.gradle.kts` 配置自己的签名。

### CI

推送 `main`/`master` 或打 `v*` tag 后，GitHub Actions 会自动构建 release APK（见 `.github/workflows/build.yml`）。

### 开源许可

[MIT](LICENSE) © 2026 VicQIAN

---

## English

### Features

**Recording**
- Timestamp defaults to now, editable for back-filling past sessions
- Session length in decimal hours (e.g. 3.5 = 3h30m)
- Venue: presets for major Macau casinos, plus custom entries
- Dual currency HKD/CNY with auto exchange-rate conversion
- Common blind levels as presets, custom values supported
- Win = green, loss = red, optional note per record

**Ledger**
- Sessions grouped into "trips" with drag-to-place break lines; one-tap to seal the current trip
- Time-range filters: all / this month / this year / last 7 days / last 30 days / custom range / pick trips
- Each card shows both HKD and CNY P/L, with a live summary bar

**Statistics**
- Net P/L overview, best/worst single sessions, per-venue breakdown

**Volatility Analysis** (in big blinds)
- Cumulative P/L curve, EV line, 95%/70% confidence bands
- Current drawdown & probability of being downswing (Monte Carlo, fixed seed → reproducible)
- Answers the question every poker player asks: "Is my downswing normal?"

**More**
- Table timer: clock in / out, duration auto-filled into the next record
- Exchange log: HKD cash-out / settlement records
- Excel import/export: full round-trip backup including trip structure
- Auto exchange-rate fetch (rotating public APIs), auto-saved

### Privacy

- All records live 100% in a local SQLite database. No upload, no telemetry, no ads SDK.
- The only `INTERNET` permission usage is fetching exchange rates on the settings page (public APIs — no personal data ever leaves the device). Everything else works fully offline.
- No storage / contacts / location permissions.

### Tech

- Flutter (CI: 3.19.0 stable; Dart >=3.0)
- sqflite · Provider · excel · share_plus / file_picker
- No backend, no accounts; charts hand-drawn with CustomPainter (no chart library)

### Build

```bash
flutter pub get
flutter run              # debug run
flutter build apk --release
```

> Note: `--release` uses the debug signing key by default (fine for personal sideloading). Configure your own signing in `android/app/build.gradle.kts` before distributing.

### CI

Pushing to `main`/`master` or tagging `v*` triggers an automated release-APK build via GitHub Actions (see `.github/workflows/build.yml`).

### License

[MIT](LICENSE) © 2026 VicQIAN
