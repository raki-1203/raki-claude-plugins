#!/usr/bin/env python3
"""eli5 지도 배치 — 박스·묶음 사각형과 화살표 선분을 계산한다.

render.py(그리기)와 validate.py(관통 검사)가 이 모듈 하나를 쓴다 — 그림과 검사가 어긋나지 않게.
segment_hits_rect 는 archify (MIT, Copyright (c) 2026 tt-a1i, 2025 Cocoon AI)
renderers/shared/geometry.mjs 의 segmentIntersectsRect 와 같은 검사다 (Liang–Barsky 선분 자르기).
"""
W, H, GX, GY, PAD, FP, FT = 180, 72, 110, 110, 30, 14, 48  # GY 는 묶음 머리(FT)+바닥(FP)을 빼고도 화살표가 보일 만큼
MAX_COLS = 5
MIN_EDGE = 40  # 이보다 짧은 화살표는 테두리·라벨에 묻혀 안 보인다 (archify 도 짧은 연결을 거부한다)


def children(view):
    """{묶음 id: [안쪽 박스 id]} — group 이 가리키는 node 가 묶음이다."""
    ids = {n["id"] for n in view.get("nodes", [])}
    kids = {}
    for n in view.get("nodes", []):
        g = n.get("group")
        if g in ids:
            kids.setdefault(g, []).append(n["id"])
    return kids


def _center(r):
    return r[0] + r[2] / 2, r[1] + r[3] / 2


def _clip(r, tx, ty):
    cx, cy = _center(r)
    dx, dy = tx - cx, ty - cy
    if not dx and not dy:
        return cx, cy
    s = min(abs(r[2] / 2 / (dx or 1e-9)), abs(r[3] / 2 / (dy or 1e-9)))
    return cx + dx * s, cy + dy * s


def compute(view):
    """{"boxes": {id: [x,y,w,h]}, "frames": {...}, "edges": [[x1,y1,x2,y2] | None], "size": [w,h]}"""
    kids = children(view)
    boxes = {}
    for n in view.get("nodes", []):
        if n["id"] in kids:
            continue
        span = n.get("span", 1)
        boxes[n["id"]] = [PAD + FP + n.get("col", 0) * (W + GX), PAD + FT + n.get("row", 0) * (H + GY),
                          span * W + (span - 1) * GX, H]
    frames = {}
    for fid, cs in kids.items():
        rs = [boxes[c] for c in cs if c in boxes]
        if rs:
            x0, y0 = min(r[0] for r in rs) - FP, min(r[1] for r in rs) - FT
            x1, y1 = max(r[0] + r[2] for r in rs) + FP, max(r[1] + r[3] for r in rs) + FP
            frames[fid] = [x0, y0, x1 - x0, y1 - y0]
    rect = {**boxes, **frames}
    edges = []
    for e in view.get("edges", []):
        a, b = rect.get(e.get("from")), rect.get(e.get("to"))
        if not a or not b:
            edges.append(None)
            continue
        x1, y1 = _clip(a, *_center(b))
        x2, y2 = _clip(b, *_center(a))
        edges.append([round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)])
    every = list(rect.values())
    return {"boxes": boxes, "frames": frames, "edges": edges,
            "size": [max((r[0] + r[2] for r in every), default=0) + PAD, max((r[1] + r[3] for r in every), default=0) + PAD]}


def segment_hits_rect(seg, r, inset=2):
    x1, y1, x2, y2 = seg
    xmin, ymin, xmax, ymax = r[0] + inset, r[1] + inset, r[0] + r[2] - inset, r[1] + r[3] - inset
    dx, dy = x2 - x1, y2 - y1
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x1 - xmin), (dx, xmax - x1), (-dy, y1 - ymin), (dy, ymax - y1)):
        if p == 0:
            if q < 0:
                return False
            continue
        t = q / p
        if p < 0:
            if t > t1:
                return False
            t0 = max(t0, t)
        else:
            if t < t0:
                return False
            t1 = min(t1, t)
    return t0 <= t1


def rects_overlap(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def problems(view, lay):
    """[(종류, 설명)] — 화살표가 상관없는 박스·묶음을 지나거나, 묶음 밖 박스가 묶음 테두리 안에 있다."""
    nodes = {n["id"]: n for n in view.get("nodes", [])}
    kids = children(view)
    name = lambda i: nodes.get(i, {}).get("title") or i
    out = []
    for bid, r in lay["boxes"].items():
        for fid, fr in lay["frames"].items():
            if nodes[bid].get("group") != fid and rects_overlap(r, fr):
                out.append(f"'{name(bid)}' 박스가 '{name(fid)}' 묶음 테두리 안에 있다 — 묶음 밖으로 옮기거나 \"group\": \"{fid}\" 를 단다")
    for i, e in enumerate(view.get("edges", [])):
        seg = lay["edges"][i]
        if not seg:
            continue
        n = ((seg[2] - seg[0]) ** 2 + (seg[3] - seg[1]) ** 2) ** 0.5
        if n < MIN_EDGE:
            out.append(f"{name(e['from'])}→{name(e['to'])} 화살표가 {n:.0f}px 로 너무 짧아 잘 안 보인다 — 두 박스(묶음) 사이를 한 칸 띄운다")
        skip = set()
        for end in (e["from"], e["to"]):
            skip.add(end)
            skip.update(kids.get(end, []))
            if nodes.get(end, {}).get("group"):
                skip.add(nodes[end]["group"])
        for oid, r in list(lay["boxes"].items()) + list(lay["frames"].items()):
            if oid not in skip and segment_hits_rect(seg, r):
                what = "묶음을" if oid in lay["frames"] else "박스를"
                out.append(f"{name(e['from'])}→{name(e['to'])} 화살표가 '{name(oid)}' {what} 지난다 — 박스를 옮겨 화살표 길을 비운다")
    return out
