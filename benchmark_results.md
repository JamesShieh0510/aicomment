# Ollama Commit Message Generation Benchmark

根據測試紀錄，整理出 Apple M3 Max 與 NVIDIA 4080 (Remote) 在不同模型下的產生時間對比。

## 測試環境
### 本地端 (Local)
- **硬體**: Apple M3 Max (128GB RAM)
- **連線**: Localhost

### 遠端伺服器 (Remote)
- **硬體**: NVIDIA RTX 4080 + Intel i7-13700K
- **連線**: 區域網路 (192.168.50.155)
- **限制**: 顯存不足以跑 70B 模型

---

## 測試數據詳情

| 執行環境 | AI 模型 | 串接方式 | 花費時間 (秒) | 備註 |
| :--- | :--- | :--- | :--- | :--- |
| **Local** | deepseek-r1:8b | CLI (aicommit) | 46s | |
| **Local** | deepseek-r1:70b | API (aicommits) | 95s | |
| **Local** | deepseek-r1:8b | API (aicommits) | 34s | |
| **Local** | deepseek-r1:8b | API (aicommits) | 76s | 可能是 Diff 長度不同 |
| **Remote** | deepseek-r1:8b | API (aicommits) | 27s | |
| **Remote** | deepseek-r1:8b | API (aicommits) | 38s | |

---

## 觀察與總結
1. **70B 性能**: 在 M3 Max 本地執行 `deepseek-r1:70b` 雖然稍慢（95秒），但在 128GB 記憶體支援下能順利完成高品質生成。
2. **8B 性能對比**: 
   - 遠端 4080 (27s - 38s) 整體速度略優於 M3 Max 本地端。
   - 同為 8B 模型，時間落差（如 34s vs 76s）通常受當次 `git diff` 內容長度及內容複雜度影響。
3. **API vs CLI**: API 版本 (`aicommits`) 支援遠端主機後，能有效利用高效能伺服器資源來加速生成流程。
4. **硬體限制**: 遠端 4080 環境受限於 VRAM，無法執行 `deepseek-r1:70b` 模型；相比之下，Apple M3 Max 憑藉其 128GB 統一記憶體優勢，成為執行大型模型的首選。
