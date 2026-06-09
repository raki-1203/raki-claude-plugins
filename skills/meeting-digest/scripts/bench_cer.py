#!/usr/bin/env python3
"""문자 단위 오류율(CER) 계산기 — 표준 라이브러리만 사용.

reference(정답으로 간주할 텍스트)와 hypothesis(비교 대상)의 char-level
edit distance를 구해 CER을 계산한다. 한국어 전사 비교용.

사용:
    bench_cer.py <reference.txt> <hypothesis.txt>
출력(공백 구분 한 줄):
    <cer_nospace%> <cer_ws%> <ref_chars> <hyp_chars>
  - cer_nospace: 모든 공백 제거 후 CER (순수 문자 인식 오류)
  - cer_ws: 연속 공백을 하나로 정규화한 CER (띄어쓰기 포함)
"""
import re
import sys


def edit_distance(a: str, b: str) -> int:
    if a == b:
        return 0
    la, lb = len(a), len(b)
    if la == 0:
        return lb
    if lb == 0:
        return la
    prev = list(range(lb + 1))
    for i in range(1, la + 1):
        cur = [i] + [0] * lb
        ca = a[i - 1]
        for j in range(1, lb + 1):
            cost = 0 if ca == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev = cur
    return prev[lb]


def cer(ref: str, hyp: str) -> float:
    if not ref:
        return 0.0 if not hyp else 100.0
    return edit_distance(ref, hyp) / len(ref) * 100.0


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: bench_cer.py <reference.txt> <hypothesis.txt>")
    ref = open(sys.argv[1], encoding="utf-8").read()
    hyp = open(sys.argv[2], encoding="utf-8").read()

    ref_ns = re.sub(r"\s+", "", ref)
    hyp_ns = re.sub(r"\s+", "", hyp)
    ref_ws = re.sub(r"\s+", " ", ref).strip()
    hyp_ws = re.sub(r"\s+", " ", hyp).strip()

    print(f"{cer(ref_ns, hyp_ns):.2f} {cer(ref_ws, hyp_ws):.2f} "
          f"{len(ref_ns)} {len(hyp_ns)}")


if __name__ == "__main__":
    main()
