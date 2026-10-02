#!/usr/bin/env python3
"""eli5 쉬운 말 검사 — 사람이 읽는 글에서 코드 이름과 풀이 없는 용어를 찾는다.

text_units 는 archify (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)
renderers/shared/utils.mjs 의 textUnits 를 옮긴 것이다 — 전각 글자는 2칸, 나머지는 1칸.
"""
import re

TITLE_MAX, SAY_MAX, LABEL_MAX = 24, 30, 18
KINDS = ("person", "external", "service", "module", "store", "job")

FULLWIDTH_RE = re.compile(
    "[ᄀ-ᅟ⺀-꓏가-힣豈-﫿︰-﹏"
    "＀-｠￠-￦\U0001F000-\U0001FAFF\U00020000-\U0003FFFD]")

# \b 는 한글도 단어 문자로 봐서 "API로" 같은 조사 결합에서 경계가 생기지 않는다. ASCII 기준 경계를 쓴다.
A = r"(?<![A-Za-z0-9_])"
Z = r"(?![A-Za-z0-9_])"
CODE = (
    ("snake_case", re.compile(A + r"[A-Za-z0-9]+_[A-Za-z0-9_]+" + Z)),
    ("camelCase", re.compile(A + r"[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*" + Z)),
    ("파일 이름", re.compile(A + r"[A-Za-z0-9_-]+\.(?:py|js|ts|tsx|jsx|json|md|ya?ml|toml|sh|go|rs|java|kt|sql|html|css)" + Z)),
    ("경로", re.compile(r"[A-Za-z0-9_.-]*/[A-Za-z0-9_./{}-]*[A-Za-z][A-Za-z0-9_./{}-]*")),
    ("함수 호출", re.compile(A + r"[A-Za-z_][A-Za-z0-9_]*\(")),
    ("속성 접근", re.compile(A + r"[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*")),
    ("심볼 표기", re.compile(r"(?:#|::)[A-Za-z_][A-Za-z0-9_]*")),
)
TERM_RE = re.compile(A + r"(?:[A-Z]{2,}[A-Za-z0-9]*|[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*)" + Z)
# glossary 키로 들어오면 안 되는 종류 — 이걸 허용하면 코드 이름을 glossary 에 넣어 검사를 피할 수 있다
KEY_FORBIDDEN = ("snake_case", "camelCase", "경로", "함수 호출", "심볼 표기")


def text_units(text):
    return sum(2 if FULLWIDTH_RE.match(ch) else 1 for ch in str(text or ""))


def _known(tok, glossary):
    return tok in glossary or (tok.endswith("s") and tok[:-1] in glossary)


def _scan(text, glossary):
    """(시작, 끝, 종류, 토큰) 을 글 순서로. 겹치는 구간은 먼저 잡힌 것만 남긴다."""
    found = []
    for kind, rx in CODE:
        for m in rx.finditer(text):
            s, e, tok = m.start(), m.end(), m.group(0)
            if any(s < fe and fs < e for fs, fe, _, _ in found):
                continue
            found.append((s, e, kind, tok))
    return sorted((f for f in found if not _known(f[3], glossary)), key=lambda f: f[0])


def code_tokens(text, glossary=None):
    return [(k, t) for _, _, k, t in _scan(str(text or ""), glossary or {})]


def unexplained_terms(text, glossary=None):
    text, glossary = str(text or ""), glossary or {}
    spans = [(s, e) for s, e, _, _ in _scan(text, glossary)]
    out = []
    for m in TERM_RE.finditer(text):
        if any(m.start() < e and s < m.end() for s, e in spans):
            continue
        if not _known(m.group(0), glossary) and m.group(0) not in out:
            out.append(m.group(0))
    return out


def check_plain(where, text, glossary, limit=None):
    errs = [f"{where} 에 '{tok}' ({kind}) — 코드 이름은 code[]·인터페이스 카드로 옮기고 하는 일을 쉬운 말로 쓴다"
            for kind, tok in code_tokens(text, glossary)]
    errs += [f"{where} 에 '{tok}' — meta.glossary 에 풀이를 추가하거나 쉬운 말로 바꾼다"
             for tok in unexplained_terms(text, glossary)]
    if limit is not None:
        u = text_units(text)
        if u > limit:
            errs.append(f"{where} 가 {u}칸, 상한 {limit} — {u - limit}칸 줄이거나 자세한 내용은 카드(detail)로 옮긴다")
    return errs


def glossary_key_errors(glossary):
    errs = []
    for key in glossary:
        kinds = [k for k, _ in code_tokens(key, {})]
        bad = any(k in KEY_FORBIDDEN for k in kinds) or (
            any(k in ("속성 접근", "파일 이름") for k in kinds) and key[:1].islower())
        if bad:
            errs.append(f"meta.glossary 키 '{key}' 는 코드 이름이다 — glossary 는 제품·기술 용어만. 코드 이름은 글에서 빼고 code[] 로 옮긴다")
    return errs
