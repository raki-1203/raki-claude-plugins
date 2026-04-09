# NotebookLM 연동 가이드

notebooklm-py CLI를 사용하여 NotebookLM과 프로그래밍 방식으로 연동한다.

## 사전 조건 확인

스킬 실행 시 가장 먼저 notebooklm-py 설치 여부와 인증 상태를 확인한다.

### 설치 확인

```bash
command -v notebooklm || pip install notebooklm
```

### 인증 확인

```bash
notebooklm auth check --test
```

실패 시 사용자에게 안내:
> "NotebookLM 인증이 필요합니다. `! notebooklm login` 을 실행하여 Google 계정으로 로그인해주세요."

인증이 불가능한 환경이면 fallback(Claude 직접 분석)으로 전환한다.

## 노트북 생성

```bash
notebooklm create "{owner}/{repo} 분석"
```

출력에서 노트북 ID를 파싱하여 이후 단계에 전달한다.

## 소스 업로드

repomix 출력 파일을 소스로 추가:

```bash
notebooklm use {notebook_id}
notebooklm source add "/tmp/repomix-{repo}.txt"
```

GitHub repo URL도 추가 소스로 등록:

```bash
notebooklm source add "https://github.com/{owner}/{repo}"
```

### 파일 크기 제한

- 20MB 초과 시 업로드가 타임아웃될 수 있음
- 대안 1: repomix의 `--compress` 옵션 사용
- 대안 2: 파일을 분할하여 여러 소스로 업로드
- 대안 3: fallback으로 전환

## 질의

노트북을 활성화한 상태에서 질문:

```bash
notebooklm use {notebook_id}
notebooklm ask "질문 내용"
```

답변은 stdout으로 출력된다. 각 질문의 답변을 수집하여 분석 문서에 포함한다.

## 콘텐츠 생성

### 리포트

```bash
notebooklm generate report --format study-guide --wait
notebooklm download report ./report.md
```

### 마인드맵

```bash
notebooklm generate mind-map --wait
notebooklm download mind-map ./mindmap.json
```

### 오디오 (팟캐스트)

```bash
notebooklm generate audio "이 프로젝트의 핵심을 설명해줘" --format deep-dive --length default --wait
notebooklm download audio ./podcast.mp3
```

### 슬라이드

```bash
notebooklm generate slide-deck --format detailed --wait
notebooklm download slide-deck ./slides.pptx --format pptx
```

### 인포그래픽

```bash
notebooklm generate infographic --orientation landscape --wait
notebooklm download infographic ./infographic.png
```

## 대화 이력 저장

```bash
notebooklm history --save
```

## Fallback: Claude 직접 분석

NotebookLM 연동 실패 시 Claude가 직접 분석한다.

### 전환 조건

다음 중 하나라도 해당하면 fallback으로 전환:
1. `notebooklm auth check --test` 실패 + 사용자가 로그인 거부
2. 소스 업로드 2회 연속 실패
3. 노트북 생성 실패

### fallback 절차

1. repomix 출력 파일을 Read 도구로 직접 읽기
2. 공통 질문 + 맞춤 질문에 대해 Claude가 직접 답변 생성
3. 리포트/마인드맵 생성은 건너뜀 (NotebookLM 전용 기능)
4. 결과 문서에 "NotebookLM 미사용 — Claude 직접 분석" 표기
5. NotebookLM 노트북 ID 항목은 "미생성" 표기
