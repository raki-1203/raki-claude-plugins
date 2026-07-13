#!/usr/bin/env python3
"""meeting-digest 화자 분리(diarization) — pyannote.audio 4.x

전용 격리 venv(~/.local/share/rakis/diarize-venv)에서 실행된다. mlx_whisper 전사와
분리된 별도 단계로, transcript.json 세그먼트에 화자 라벨을 붙인다.

흐름:
  1. ffmpeg CLI로 오디오 → 16kHz mono wav (torchcodec 우회)
  2. soundfile로 waveform 로드 → pyannote에 dict로 직접 전달
     (torchcodec가 시스템 ffmpeg 버전 불일치로 깨져서, pyannote 공식 우회 경로 사용)
  3. pyannote/speaker-diarization-community-1 (gated) 파이프라인 실행
  4. 화자 구간 ↔ transcript.json 세그먼트 시간 겹침으로 라벨 배정
  5. transcript.speakers.json + transcript.speakers.txt 생성

Usage:
  diarize.py --audio <path> --transcript-json <path> --out-dir <dir>
             [--num-speakers N] [--hf-token TOKEN]
  diarize.py --self-check      # ML 없이 배정 로직만 검증

HF 토큰: --hf-token 또는 env HF_TOKEN / HUGGINGFACE_TOKEN.
  gated 모델이라 https://hf.co/pyannote/speaker-diarization-community-1 에서
  이용약관 동의 필요.

Exit codes:
  0  성공
  2  의존성 누락 (pyannote/soundfile/ffmpeg)
  3  오디오/transcript 파일 문제
  5  HF 토큰 없음
  6  모델 로드/전사 실패 (gated 미동의·네트워크 등)
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

MODEL = "pyannote/speaker-diarization-community-1"


def eprint(*a):
    print(*a, file=sys.stderr)


def assign_speakers(segments, turns):
    """각 transcript 세그먼트에 시간 겹침이 가장 큰 화자 라벨을 배정.

    segments: [{"start","end","text",...}]
    turns:    [(start, end, label)]  — pyannote 화자 구간
    반환: segments (각 dict에 "speaker" 추가; 겹침 없으면 None)
    """
    for seg in segments:
        s, e = seg["start"], seg["end"]
        best_label, best_ov = None, 0.0
        for ts, te, label in turns:
            ov = min(e, te) - max(s, ts)
            if ov > best_ov:
                best_ov, best_label = ov, label
        seg["speaker"] = best_label
    return segments


def relabel(segments):
    """SPEAKER_00, SPEAKER_01... → 등장 순서대로 화자1, 화자2. None → 미상."""
    order = {}
    for seg in segments:
        lab = seg["speaker"]
        if lab is not None and lab not in order:
            order[lab] = f"화자{len(order) + 1}"
    for seg in segments:
        seg["speaker"] = order.get(seg["speaker"], "미상")
    return segments


def to_speaker_text(segments):
    """연속 동일 화자 세그먼트를 묶어 '[화자N] 텍스트' 블록으로."""
    lines, cur, buf = [], None, []
    for seg in segments:
        spk, text = seg["speaker"], seg["text"].strip()
        if not text:
            continue
        if spk != cur and buf:
            lines.append(f"[{cur}] {' '.join(buf)}")
            buf = []
        cur, buf = spk, buf + [text]
    if buf:
        lines.append(f"[{cur}] {' '.join(buf)}")
    return "\n\n".join(lines) + "\n"


def _self_check():
    segs = [
        {"start": 0.0, "end": 2.0, "text": "a"},
        {"start": 2.0, "end": 4.0, "text": "b"},
        {"start": 4.0, "end": 6.0, "text": "c"},
    ]
    turns = [(0.0, 2.1, "SPEAKER_00"), (2.0, 3.95, "SPEAKER_01"), (3.9, 6.0, "SPEAKER_00")]
    out = assign_speakers([dict(x) for x in segs], turns)
    assert [s["speaker"] for s in out] == ["SPEAKER_00", "SPEAKER_01", "SPEAKER_00"], out
    # 겹침 없는 세그먼트 → None
    out2 = assign_speakers([{"start": 10.0, "end": 11.0, "text": "x"}], turns)
    assert out2[0]["speaker"] is None, out2
    # relabel + text
    rl = relabel(assign_speakers([dict(x) for x in segs], turns))
    assert [s["speaker"] for s in rl] == ["화자1", "화자2", "화자1"], rl
    txt = to_speaker_text(rl)
    assert txt.startswith("[화자1] a\n\n[화자2] b\n\n[화자1] c"), repr(txt)
    print("self-check OK")


def ffmpeg_to_wav(audio, wav_path):
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
         "-i", audio, "-ar", "16000", "-ac", "1", wav_path],
        check=True,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audio")
    ap.add_argument("--transcript-json")
    ap.add_argument("--out-dir")
    ap.add_argument("--num-speakers", type=int, default=None)
    ap.add_argument("--hf-token", default=None)
    ap.add_argument("--self-check", action="store_true")
    args = ap.parse_args()

    if args.self_check:
        _self_check()
        return 0

    if not (args.audio and args.transcript_json and args.out_dir):
        eprint("usage: diarize.py --audio X --transcript-json Y --out-dir Z")
        return 3

    token = args.hf_token or os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_TOKEN")
    if not token:
        eprint("❌ HF 토큰 없음 (env HF_TOKEN 또는 --hf-token)")
        return 5

    if not os.path.isfile(args.audio):
        eprint(f"❌ 오디오 없음: {args.audio}")
        return 3
    if not os.path.isfile(args.transcript_json):
        eprint(f"❌ transcript.json 없음: {args.transcript_json}")
        return 3

    try:
        import soundfile as sf
        import torch
        from pyannote.audio import Pipeline
    except ImportError as e:
        eprint(f"❌ 의존성 누락: {e} — /rakis:setup 재실행")
        return 2

    with open(args.transcript_json, encoding="utf-8") as f:
        segments = json.load(f).get("segments", [])
    if not segments:
        eprint("❌ transcript.json에 segments 없음")
        return 3

    # 오디오 → 16kHz mono wav → waveform 텐서 (torchcodec 우회)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "audio.16k.wav")
        try:
            ffmpeg_to_wav(args.audio, wav)
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            eprint(f"❌ ffmpeg 변환 실패: {e}")
            return 2
        data, sr = sf.read(wav, dtype="float32", always_2d=True)  # (T, C)
        waveform = torch.from_numpy(data.T)  # (C, T) = (1, T)

        eprint(f"▶ 화자 분리 시작 (model={MODEL})")
        eprint("  (첫 실행 시 모델 다운로드 발생)")
        try:
            pipeline = Pipeline.from_pretrained(MODEL, token=token)
        except Exception as e:
            eprint(f"❌ 파이프라인 로드 실패: {e}")
            eprint(f"   gated 모델 이용약관 동의 확인: https://hf.co/{MODEL}")
            return 6

        device = "mps" if torch.backends.mps.is_available() else "cpu"
        pipeline.to(torch.device(device))
        eprint(f"  device={device}")

        kw = {}
        if args.num_speakers:
            kw["num_speakers"] = args.num_speakers
        try:
            result = pipeline({"waveform": waveform, "sample_rate": sr}, **kw)
        except Exception as e:
            eprint(f"❌ 화자 분리 실패: {e}")
            return 6

    # pyannote 4.x는 결과를 래핑(.speaker_diarization), 3.x는 Annotation 직접
    ann = getattr(result, "speaker_diarization", result)
    turns = [(seg.start, seg.end, label) for seg, _, label in ann.itertracks(yield_label=True)]
    if not turns:
        eprint("⚠ 화자 구간 0개 — 배정 생략")
        return 6

    relabel(assign_speakers(segments, turns))
    n_speakers = len({s["speaker"] for s in segments} - {"미상"})

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "transcript.speakers.json"), "w", encoding="utf-8") as f:
        json.dump({"speakers": n_speakers, "segments": segments}, f, ensure_ascii=False, indent=2)
    with open(os.path.join(args.out_dir, "transcript.speakers.txt"), "w", encoding="utf-8") as f:
        f.write(to_speaker_text(segments))

    print(f"✓ 화자 분리 완료: {n_speakers}명 / {len(segments)}개 세그먼트")
    print(f"  → {args.out_dir}/transcript.speakers.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
