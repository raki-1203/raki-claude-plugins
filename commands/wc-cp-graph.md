---
description: 메인 worktree의 graphify 관련 파일을 현재 worktree로 복사 (graphify-out + CLAUDE.md + .claude/settings.json)
---

메인 worktree에서 graphify 관련 파일을 현재 디렉토리로 복사합니다.

## 절차

1. 메인 worktree 경로:
   ```bash
   MAIN_DIR=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
   ```

2. **graphify-out 복사**:
   - `graphify-out/GRAPH_REPORT.md` 이미 있으면 skip
   - 메인에 없으면 "메인에 graphify-out이 없습니다" 보고
   - 기존 빈 폴더가 있으면 삭제 후 복사:
     ```bash
     rm -rf ./graphify-out
     cp -r "$MAIN_DIR/graphify-out" ./graphify-out
     ```

3. **CLAUDE.md 복사**:
   - 메인에 `CLAUDE.md` 있으면 복사:
     ```bash
     cp "$MAIN_DIR/CLAUDE.md" ./CLAUDE.md
     ```
   - 없으면 skip

4. **.claude/settings.json 복사**:
   - 메인에 `.claude/settings.json` 있으면 복사:
     ```bash
     mkdir -p .claude
     cp "$MAIN_DIR/.claude/settings.json" .claude/settings.json
     ```
   - 없으면 skip

5. 결과 보고 (각 항목별 복사됨/skip/없음)
