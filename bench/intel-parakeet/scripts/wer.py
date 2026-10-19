import json, re, sys
ONES = "zero one two three four five six seven eight nine".split()

def spell_number(m):
    s = m.group(0)
    if "." in s:
        a, b = s.split(".", 1)
        return " ".join([spell_int(a), "point"] + [ONES[int(c)] for c in b])
    return spell_int(s)

def spell_int(s):
    n = int(s)
    teens = "ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
    tens = "_ _ twenty thirty forty fifty sixty seventy eighty ninety".split()
    if n < 10: return ONES[n]
    if n < 20: return teens[n - 10]
    if n < 100: return tens[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    return s

def norm(t):
    t = t.lower()
    t = re.sub(r"\d+(\.\d+)?", spell_number, t)
    t = re.sub(r"[^a-z0-9' ]+", " ", t).replace("'", "")
    return t.split()

def wer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        prev, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            cur = d[j]
            d[j] = min(d[j] + 1, d[j - 1] + 1, prev + (r[i - 1] != h[j - 1]))
            prev = cur
    return d[len(h)] / len(r), d[len(h)], len(r)

def diff_words(ref, hyp):
    import difflib
    r, h = norm(ref), norm(hyp)
    out = []
    for op, a1, a2, b1, b2 in difflib.SequenceMatcher(a=r, b=h).get_opcodes():
        if op != "equal":
            out.append(f"{op}: '{' '.join(r[a1:a2])}' -> '{' '.join(h[b1:b2])}'")
    return out

if __name__ == "__main__":
    ref = open(sys.argv[1]).read()
    for p in sys.argv[2:]:
        hyp = json.load(open(p))["hyp_text"] if p.endswith(".json") else open(p).read()
        w, e, n = wer(ref, hyp)
        print(f"{p.rsplit('/',1)[-1]}\tWER={w*100:.2f}% ({e}/{n})\t{'; '.join(diff_words(ref, hyp))}")
