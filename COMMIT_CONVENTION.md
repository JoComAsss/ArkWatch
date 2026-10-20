# 提交信息与署名约定

本项目采用 **commit trailer** 标注协作来源，便于回溯每次改动的参与方。

## 启用模板

克隆仓库后执行一次：

```bash
git config commit.template .gitmessage
```

之后 `git commit` 会自动预填模板（`#` 开头的说明行不会进入提交信息）。

## Trailer 格式

提交信息末尾保留以下两行：

```
Assisted-by: DeepSeek Harness
Co-authored-by: DeepSeek <noreply@deepseek.com>
```

| Trailer | 含义 |
|---|---|
| `Assisted-by` | 标记本次改动由 AI 工具协助完成，便于审计与追溯 |
| `Co-authored-by` | GitHub 会将其识别为共同作者，提交头像与贡献统计中可见 |

## 规范

1. trailer 必须位于提交信息的**最后一段**，每行形如 `Key: Value`；
2. trailer 与正文之间保留一个空行，不要加分隔线；
3. 手工提交时不要删除模板中的 trailer；
4. 如果某次提交完全没有 AI 参与，可自行删掉这两行——但请保持诚实，不要伪造归属。
