"""Summarize a runs/ directory written by bench.sh as Markdown.

usage: python3 -I aggregate.py <runs_dir> <reference.txt>
"""
import glob
import json
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wer import diff_words, wer  # noqa: E402


def time_stats(errfile):
    """Wall, CPU seconds and max RSS from /usr/bin/time -l output, if present."""
    try:
        text = open(errfile).read()
    except OSError:
        return None, None, None
    m = re.search(r"([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys", text)
    rss = re.search(r"(\d+)\s+maximum resident set size", text)
    if not m:
        return None, None, None
    return float(m.group(1)), float(m.group(2)) + float(m.group(3)), (int(rss.group(1)) if rss else None)


def load_tcpp(path, ref):
    d = json.load(open(path))
    name = os.path.basename(path)[:-5]
    walls = [it["wall_ms"] / 1000 for it in d["per_iter"]]
    m = re.match(r"tcpp-(x86_64|arm64)-(Q\w+?)-t(\d+)", name)
    real, cpu, rss = time_stats(path[:-5] + ".err")
    w, _, _ = wer(ref, d["hyp_text"])
    return dict(name=name, engine="transcribe.cpp", arch=m.group(1), variant=m.group(2), threads=m.group(3),
                load=d["load_ms"] / 1000, cold=walls[0], warm_list=walls[1:],
                warm=statistics.mean(walls[1:]) if len(walls) > 1 else walls[0],
                encode=d["summary"]["encode_ms"]["mean"] / 1000, decode=d["summary"]["decode_ms"]["mean"] / 1000,
                audio=d["sample_duration_s"], wer=w, real=real, cpu=cpu, rss=rss, text=d["hyp_text"].strip())


def load_coreml(path, ref):
    name = os.path.basename(path)[:-4]
    out = open(path).read()
    if "RESULT" not in out:
        return None
    fields = dict(re.findall(r"(\w+)=([^\s]+)", out.split("RESULT", 1)[1]))
    warm_list = [float(x) for x in fields["warm"].split(",")] if fields["warm"] != "-" else []
    real, cpu, rss = time_stats(path[:-4] + ".err")
    text = open(path[:-4] + ".txt").read().strip()
    w, _, _ = wer(ref, text)
    return dict(name=name, engine="CoreML", arch=fields["arch"], variant=fields["units"], threads="CoreML",
                load=float(fields["load"]), cold=float(fields["cold"]), warm_list=warm_list,
                warm=float(fields["warm_mean"]), encode=None, decode=None, audio=float(fields["audio"]), wer=w,
                real=real, cpu=cpu, rss=rss, text=text)


def fmt(v, spec=".2f"):
    return "—" if v is None else format(v, spec)


def main():
    runs, ref_path = sys.argv[1], sys.argv[2]
    ref = open(ref_path).read()
    rows = []
    for p in sorted(glob.glob(f"{runs}/coreml-*.out")):
        r = load_coreml(p, ref)
        if r:
            rows.append(r)
    for p in sorted(glob.glob(f"{runs}/tcpp-*.json")):
        try:
            rows.append(load_tcpp(p, ref))
        except (ValueError, KeyError, IndexError) as e:
            print(f"<!-- could not parse {p}: {e} -->")

    print("# Parakeet TDT 0.6B v3: CoreML vs transcribe.cpp on the CPU\n")
    hw = os.path.join(runs, "hardware.txt")
    if os.path.exists(hw):
        print("```\n" + open(hw).read().strip() + "\n```\n")
    rev = os.path.join(runs, "coreml-revision.txt")
    if os.path.exists(rev):
        print(f"CoreML models: `{open(rev).read().strip()}`\n")

    groups = {}
    for r in rows:
        groups.setdefault((r["engine"], r["arch"], r["variant"], r["threads"]), []).append(r)

    print("## Summary (medians across processes)\n")
    print("Seconds for the full clip. Cold = first transcription after load; warm = mean of the later runs. "
          "First load = load time of the first process (includes any CoreML compile).\n")
    print("| engine | arch | quant / units | threads | first load s | load s | cold s | warm s | RTFx | WER | procs |")
    print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for (engine, arch, variant, threads), rs in groups.items():
        warm = statistics.median(r["warm"] for r in rs)
        print(f"| {engine} | {arch} | {variant} | {threads} | {rs[0]['load']:.2f} | "
              f"{statistics.median(r['load'] for r in rs):.2f} | {statistics.median(r['cold'] for r in rs):.2f} | "
              f"**{warm:.2f}** | {rs[0]['audio'] / warm:.1f}x | "
              f"{statistics.median(r['wer'] for r in rs) * 100:.2f}% | {len(rs)} |")

    print("\n## Every process\n")
    print("| run | load s | cold s | warm s | warm runs | encode s | decode s | RTFx | WER | wall s | CPU s | avg cores | max RSS MB |")
    print("|---|---:|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for r in rows:
        cores = r["cpu"] / r["real"] if r["cpu"] and r["real"] else None
        rss = r["rss"] / 1048576 if r["rss"] else None
        print(f"| {r['name']} | {r['load']:.2f} | {r['cold']:.2f} | {r['warm']:.2f} | "
              f"{', '.join(f'{x:.2f}' for x in r['warm_list'])} | {fmt(r['encode'])} | {fmt(r['decode'])} | "
              f"{r['audio'] / r['warm']:.1f}x | {r['wer'] * 100:.2f}% | {fmt(r['real'], '.1f')} | "
              f"{fmt(r['cpu'], '.0f')} | {fmt(cores, '.1f')} | {fmt(rss, '.0f')} |")

    status = os.path.join(runs, "status.tsv")
    if os.path.exists(status):
        failed = [line.split("\t") for line in open(status).read().splitlines() if line and not line.endswith("\t0")]
        if failed:
            print("\n## Failed configs\n")
            for name, code in failed:
                print(f"- `{name}`: exit {code}")
    errors = os.path.join(runs, "errors.md")
    if os.path.exists(errors):
        print("\n## Errors\n")
        print(open(errors).read())

    print("\n## Transcripts\n")
    distinct = {}
    for r in rows:
        distinct.setdefault(r["text"], []).append(r["name"])
    for text, names in distinct.items():
        diffs = diff_words(ref, text)
        print(f"- **{len(names)} run(s)**: {', '.join(names)}")
        print(f"  - differences from the reference: {'; '.join(diffs) if diffs else 'none'}")
        print(f"  - first 200 chars: {text[:200]!r}")


if __name__ == "__main__":
    main()
