#!/usr/bin/env python3
"""전사 텍스트의 반복(환각 루프) 지표 — 표준 라이브러리만 사용.

whisper 계열은 far-field·저SNR 구간에서 같은 구절을 무한 반복하는 환각을 낸다.
CER은 이걸 못 잡으므로(기준 자체가 틀릴 수 있음) 별도로 잰다.

사용:
    bench_repeat.py <transcript.txt>
출력(공백 구분 한 줄):
    <최장연속반복횟수> <반복문자비율%> <고유4gram비율%> <총문자수>
"""
import re
import sys
from collections import Counter


def longest_run(text: str, n: int = 4) -> int:
    """길이 n 이상 구절이 연속으로 몇 번 반복되는지 최대값."""
    best = 1
    for size in range(n, min(60, len(text) // 2 + 1)):
        i = 0
        while i + size <= len(text):
            unit = text[i:i + size]
            count = 1
            j = i + size
            while text[j:j + size] == unit:
                count += 1
                j += size
            if count > best:
                best = count
            i += 1 if count == 1 else (count * size)
    return best


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: bench_repeat.py <transcript.txt>")
    text = re.sub(r"\s+", "", open(sys.argv[1], encoding="utf-8").read())
    if not text:
        print("0 0.00 0.00 0")
        return

    grams = [text[i:i + 4] for i in range(len(text) - 3)]
    counts = Counter(grams)
    uniq_ratio = len(counts) / len(grams) * 100 if grams else 0.0
    # 3회 이상 등장한 4-gram이 차지하는 문자 비율
    repeated = sum(c * 4 for c in counts.values() if c >= 3)
    rep_ratio = min(100.0, repeated / len(text) * 100)

    print(f"{longest_run(text)} {rep_ratio:.2f} {uniq_ratio:.2f} {len(text)}")


if __name__ == "__main__":
    main()
