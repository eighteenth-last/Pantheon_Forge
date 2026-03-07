# Pantheon Forge

<p align="center">
  <img src="assets/logo.png" alt="Pantheon Forge Logo" width="128" height="128"/>
</p>

<p align="center">
  <strong>AI 智能体协作平台</strong><br>
  AI Agent Collaboration Platform
</p>

---

## 项目简介

Pantheon Forge 是一个功能强大的桌面应用程序，旨在为用户提供与 AI 智能体协作的流畅体验。通过支持多种 LLM 提供商、灵活的会话管理和丰富的自定义选项，Pantheon Forge 能够满足各种 AI 对话和协作需求。

## 主要特性

### 🤖 多提供商支持
- **OpenAI** - 支持 GPT 系列模型
- **Anthropic** - 支持 Claude 系列模型
- 支持自定义 API 端点和模型配置
- 兼容 OpenAI 兼容模式的第三方提供商

### 💬 智能对话
- 多会话管理，支持会话置顶、删除
- 流式响应，实时显示 AI 回复
- Markdown 渲染，代码高亮显示
- Token 使用统计
- 上下文管理

### ⚙️ 灵活配置
- 浅色/深色/系统主题切换
- 中英文双语支持
- 可调节 Temperature 和 Max Tokens
- 自定义 System Prompt
- 思考模式支持（适用于支持的模型）

### 🖥️ 桌面级体验
- 隐藏标题栏的原生窗口体验
- 最小化窗口尺寸限制
- 侧边栏可折叠
- 数据存储在可执行文件所在目录

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.11+ |
| 状态管理 | Riverpod |
| 数据库 | SQLite3 |
| HTTP 客户端 | Dio |
| 窗口管理 | window_manager |
| UI 组件 | Material Design 3 |

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── app.dart                     # 应用根组件
├── core/
│   ├── database/
│   │   └── database.dart       # SQLite 数据库管理
│   ├── storage/
│   │   └── storage_manager.dart # 文件存储管理
│   ├── theme/
│   │   └── app_theme.dart      # 主题配置
│   └── l10n/
│       └── translations.dart   # 国际化翻译
├── models/
│   └── models.dart             # 数据模型定义
├── providers/
│   └── app_providers.dart      # 状态管理提供者
├── services/
│   ├── api/
│   │   ├── llm_api.dart        # LLM API 调用
│   │   └── model_fetcher.dart  # 模型获取
│   └── agent/
│       └── chat_service.dart   # 聊天服务
└── ui/
    ├── layout/
    │   ├── main_layout.dart     # 主布局
    │   ├── nav_rail.dart       # 导航栏
    │   ├── session_list_panel.dart # 会话列表
    │   └── title_bar.dart       # 标题栏
    ├── chat/
    │   ├── chat_home_page.dart  # 聊天首页
    │   └── chat_view.dart       # 聊天视图
    ├── settings/
    │   ├── settings_page.dart   # 设置页面
    │   └── provider_panel.dart  # 提供商面板
    └── cowork/
        └── right_panel.dart     # 右侧面板
```

## 核心模块说明

### 数据模型 (`lib/models/models.dart`)
- `AIModelConfig` - AI 模型配置
- `AIProvider` - AI 服务提供商
- `UnifiedMessage` - 统一消息格式
- `ChatSession` - 聊天会话
- `AppSettings` - 应用设置

### 状态管理 (`lib/providers/app_providers.dart`)
- `settingsProvider` - 设置状态管理
- `uiProvider` - UI 状态管理
- `providerProvider` - 提供商状态管理
- `chatProvider` - 聊天状态管理

### API 服务 (`lib/services/api/llm_api.dart`)
- 支持 OpenAI Chat Completions API
- 支持 Anthropic Messages API
- 流式响应处理
- 工具调用支持

### 数据库 (`lib/core/database/database.dart`)
- SQLite 数据库存储
- WAL 模式提升性能
- 会话、消息、提供商、设置等表结构

## 构建与运行

### 环境要求
- Flutter SDK 3.11+
- Windows 10/11
- Visual Studio Build Tools

### 开发模式运行
```bash
flutter run
```

### 构建发布版本
```bash
flutter build windows --release
```

构建产物位于 `build/windows/x64/release/` 目录。

## 使用指南

### 1. 添加 AI 提供商
1. 打开设置页面（点击导航栏设置图标）
2. 切换到「供应商」标签
3. 点击「添加供应商」
4. 填写提供商信息：
   - 名称：自定义名称
   - 类型：OpenAI 或 Anthropic
   - API Key：您的 API 密钥
   - Base URL：（可选）自定义 API 端点
5. 添加模型配置
6. 启用提供商并设为激活

### 2. 开始对话
1. 点击左侧会话列表的「+」创建新会话
2. 在输入框输入消息
3. 按 Enter 或点击发送按钮
4. 等待 AI 响应

### 3. 自定义设置
- **主题**：在「通用」设置中选择浅色、深色或跟随系统
- **语言**：支持中文和英文
- **模型参数**：调整 Temperature、Max Tokens 等参数

## 配置示例

### OpenAI 提供商
```yaml
名称: OpenAI
类型: openai
API Key: sk-xxxxx
Base URL: https://api.openai.com (默认)
```

### Anthropic 提供商
```yaml
名称: Anthropic
类型: anthropic
API Key: sk-ant-xxxxx
Base URL: https://api.anthropic.com (默认)
```

### 兼容第三方 API
```yaml
名称: 自定义兼容
类型: openai
API Key: xxxxx
Base URL: https://your-custom-endpoint.com/v1
```

## 注意事项

1. **API 密钥安全**：请妥善保管您的 API 密钥，不要泄露给他人
2. **数据存储**：应用数据存储在可执行文件所在目录的 `.pantheon_forge/` 文件夹中
3. **网络访问**：使用代理时，请确保 API 请求可以正常访问
4. **版本信息**：当前版本为 0.1.0

## 许可证

MIT License

## 版本历史

- **0.1.0** - 初始版本
  - 多提供商支持
  - 基础对话功能
  - 会话管理
  - 主题和语言设置
