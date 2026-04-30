---
description: 메인 worktree의 gitignored graphify 자산을 현재 worktree로 복사 (graphify-out + .claude/settings.local.json)
---

메인 worktree에서 graphify 관련 **gitignored** 파일을 현재 디렉토리로 복사합니다.

> tracked 파일(`CLAUDE.md`, `.claude/settings.json`)은 worktree 생성 시 브랜치에서 자동으로 따라오므로 복사하지 않습니다. 메인에서 덮어쓰면 브랜치별 차이가 사라지는 부작용이 있습니다.

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

3. **.claude/settings.local.json 복사** (graphify PreToolUse 훅 포함):
   - 워크트리에 이미 `.claude/settings.local.json`이 있으면:
     - graphify PreToolUse 훅(`graphify-out/graph.json` 문자열)이 있는지 확인
     - 있으면 skip ("이미 graphify 훅 등록됨")
     - 없으면 사용자에게 "기존 local settings에 graphify 훅을 머지할까요?" 묻고 자동 덮어쓰기 금지
   - 없으면 메인에서 복사:
     ```bash
     mkdir -p .claude
     cp "$MAIN_DIR/.claude/settings.local.json" .claude/settings.local.json
     ```
   - 메인에도 없으면 "메인에 settings.local.json이 없습니다" 보고

4. 결과 보고 (각 항목별 복사됨/skip/없음)
