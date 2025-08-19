
#!/usr/bin/env python3
import argparse, ast, sys
from typing import List, Dict, Tuple, Set
import pandas as pd

EMOTION_MAP = {
    "happy":"joy","excited":"joy","proud":"joy","grateful":"joy","relieved":"joy",
    "motivated":"joy","loved":"joy","satisfied":"joy",
    "sad":"sadness","lonely":"sadness","tired":"sadness","ashamed":"sadness",
    "embarrassed":"sadness","bored":"sadness","guilty":"sadness",
    "angry":"anger","frustrated":"anger",
    "afraid":"fear","anxious":"fear","stressed":"fear",
    "surprised":"surprise",
    "disgusted":"disgust",
    "neutral":"neutral","mixed":"mixed"
}

DOMAIN_ALIAS = {
    "exercise": "exercise/fitness", "fitness": "exercise/fitness", "exercise/fitness": "exercise/fitness",
    "family": "family",
    "friends": "friends",
    "relationships": "relationships/marriage/partnership","marriage":"relationships/marriage/partnership",
    "partnership":"relationships/marriage/partnership","relationships/marriage/partnership":"relationships/marriage/partnership",
    "love":"love/romance","romance":"love/romance","love/romance":"love/romance",
    "food":"food/eating","eating":"food/eating","food/eating":"food/eating",
    "sleep":"sleep/rest","rest":"sleep/rest","sleep/rest":"sleep/rest",
    "health":"health/medical","medical":"health/medical","health/medical":"health/medical",
    "work":"work/career","career":"work/career","work/career":"work/career",
    "money":"money/finances","finances":"money/finances","finance":"money/finances","money/finances":"money/finances",
    "school":"school/learning","learning":"school/learning","school/learning":"school/learning",
    "spirituality":"spirituality/religion","religion":"spirituality/religion","spirituality/religion":"spirituality/religion",
    "recreation":"recreation/leisure","leisure":"recreation/leisure","recreation/leisure":"recreation/leisure",
    "travel":"travel/nature","nature":"travel/nature","travel/nature":"travel/nature",
    "creativity":"creativity/art","art":"creativity/art","creativity/art":"creativity/art",
    "community":"community/society/politics","society":"community/society/politics","politics":"community/society/politics",
    "community/society/politics":"community/society/politics",
    "technology":"technology/media/internet","media":"technology/media/internet","internet":"technology/media/internet",
    "technology/media/internet":"technology/media/internet",
    "self":"self/growth/habits","growth":"self/growth/habits","habits":"self/growth/habits","self/growth/habits":"self/growth/habits"
}

EMOTION_ADJ = {
    "joy": {"neutral"},
    "neutral": {"joy", "sadness"},
    "sadness": {"anger", "fear", "neutral"},
    "anger": {"sadness"},
    "fear": {"sadness"},
    "surprise": set(),
    "disgust": {"anger", "sadness"},
    "mixed": {"joy","sadness","anger","fear","surprise","disgust","neutral"}
}

DOMAIN_ADJ = {
    ("love/romance","relationships/marriage/partnership"),
    ("work/career","money/finances"),
    ("health/medical","exercise/fitness"),
    ("food/eating","health/medical"),
    ("family","friends"),
    ("travel/nature","recreation/leisure"),
    ("creativity/art","recreation/leisure"),
    ("technology/media/internet","recreation/leisure"),
    ("school/learning","self/growth/habits")
}

def ensure_list(x):
    if isinstance(x, list): return x
    if isinstance(x, str):
        try: return ast.literal_eval(x)
        except Exception: return []
    return []

def normalize_emotion_label(e: str) -> str:
    if e is None: return ""
    s = str(e)
    for k in ["Joy","Sadness","Anger","Fear","Surprise","Disgust","Neutral","Mixed"]:
        if k in s: return k.lower()
    return s.strip().lower()

def canonical_domain(s: str) -> str:
    if s is None: return ""
    s = str(s).strip().lower()
    return DOMAIN_ALIAS.get(s, s)

def is_domain_adjacent(a: str, b: str) -> bool:
    if not a or not b: return False
    x, y = a.lower(), b.lower()
    return x == y or (x,y) in DOMAIN_ADJ or (y,x) in DOMAIN_ADJ

def main(args):
    df = pd.read_csv(args.input)

    # Build manual labels from boolean columns if not present
    if "manual_emotions" not in df.columns or "manual_domains" not in df.columns:
        emo_cols = [c for c in df.columns if c.startswith("Answer.f1.")]
        dom_cols = [c for c in df.columns if c.startswith("Answer.t1.")]
        def get_labels(row, cols, prefix):
            out = []
            for c in cols:
                v = row.get(c, False)
                if v is True:
                    out.append(c.replace(prefix,"").replace(".raw","").strip().lower())
            return out
        df["manual_emotions"] = df.apply(lambda r: get_labels(r, emo_cols, "Answer.f1."), axis=1)
        df["manual_domains"]  = df.apply(lambda r: get_labels(r, dom_cols, "Answer.t1."), axis=1)
    else:
        df["manual_emotions"] = df["manual_emotions"].apply(ensure_list)
        df["manual_domains"]  = df["manual_domains"].apply(ensure_list)

    # Map manual emotions to coarse buckets
    def map_manual_emotions(lst: List[str]) -> List[str]:
        return sorted(set([EMOTION_MAP.get(x, x) for x in lst]))
    df["manual_emotions_coarse"] = df["manual_emotions"].apply(map_manual_emotions)

    # Normalize classifier outputs
    df["classifier_emotion_norm"] = df["EmotionPro"].astype(str).str.split("–").str[-1].str.strip().apply(normalize_emotion_label)
    df["classifier_domain_norm"]  = df["DomainPro"].astype(str).str.lower().str.strip().apply(canonical_domain)

    # Canonicalize manual domains
    df["manual_domains_canon"] = df["manual_domains"].apply(lambda lst: [canonical_domain(x) for x in lst])

    # Buckets
    def bucket_emotion(row) -> int:
        mset = set(row["manual_emotions_coarse"])
        c = row["classifier_emotion_norm"]
        if not mset and not c: return 2
        if c in mset: return 1
        if c == "mixed" and len(mset) > 1: return 2
        if any((c in EMOTION_ADJ and mm in EMOTION_ADJ[c]) or (mm in EMOTION_ADJ and c in EMOTION_ADJ[mm]) for mm in mset):
            return 2
        return 3

    def bucket_domain(row) -> int:
        mset = set([x for x in row["manual_domains_canon"] if x])
        c = row["classifier_domain_norm"]
        if not mset and not c: return 2
        if c in mset: return 1
        if "/" in c and any(p in mset for p in c.split("/")): return 1
        if any(is_domain_adjacent(c, mm) for mm in mset): return 2
        return 3

    df["bucket_emotion"] = df.apply(bucket_emotion, axis=1)
    df["bucket_domain"]  = df.apply(bucket_domain,  axis=1)

    # Counts
    emotion_counts = df["bucket_emotion"].value_counts().sort_index()
    domain_counts  = df["bucket_domain"].value_counts().sort_index()

    # Confusion matrices (mismatches only)
    mm_e = df[df["bucket_emotion"] == 3]
    emo_pairs = []
    for _, row in mm_e.iterrows():
        pred = row["classifier_emotion_norm"]
        for m in row["manual_emotions_coarse"]:
            emo_pairs.append((m, pred))
    emo_df = pd.DataFrame(emo_pairs, columns=["manual","predicted"])
    emo_cm = pd.crosstab(emo_df["manual"], emo_df["predicted"])

    mm_d = df[df["bucket_domain"] == 3]
    dom_pairs = []
    for _, row in mm_d.iterrows():
        pred = row["classifier_domain_norm"]
        for m in row["manual_domains_canon"]:
            dom_pairs.append((m, pred))
    dom_df = pd.DataFrame(dom_pairs, columns=["manual","predicted"])
    dom_cm = pd.crosstab(dom_df["manual"], dom_df["predicted"])

    # Output paths
    out_aug   = args.output or args.input.replace(".csv","_with_buckets.csv")
    out_emo   = args.emotion_cm or args.input.replace(".csv","_emotion_cm.csv")
    out_dom   = args.domain_cm  or args.input.replace(".csv","_domain_cm.csv")

    df.to_csv(out_aug, index=False)
    emo_cm.to_csv(out_emo)
    dom_cm.to_csv(out_dom)

    # Print a small summary to stdout
    def fmt_count(s):
        return {int(k): int(v) for k,v in s.to_dict().items()}
    summary = {
        "emotion_buckets": fmt_count(emotion_counts),
        "domain_buckets":  fmt_count(domain_counts),
        "outputs": {
            "augmented_csv": out_aug,
            "emotion_confusion_csv": out_emo,
            "domain_confusion_csv": out_dom
        }
    }
    print(summary)

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Evaluate classifier outputs vs manual labels with adjacency-aware bucketing.")
    p.add_argument("input", help="Input CSV from test rig")
    p.add_argument("--output", help="Augmented CSV output path (default: *_with_buckets.csv)")
    p.add_argument("--emotion-cm", help="Emotion confusion matrix CSV path (default: *_emotion_cm.csv)")
    p.add_argument("--domain-cm", help="Domain confusion matrix CSV path (default: *_domain_cm.csv)")
    args = p.parse_args()
    sys.exit(main(args))
