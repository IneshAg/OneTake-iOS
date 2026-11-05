#!/usr/bin/env python3
"""
OneTake Qwen BPE Tokenizer Parity Test
======================================
Tests mathematical equivalence between Hugging Face's official tokenizers
and custom Byte-Level BPE tokenizer implementation.
"""

import sys
import json
from pathlib import Path
import regex

BASE_DIR = Path(__file__).resolve().parent.parent
MODEL_DIR = BASE_DIR / "models" / "onetake-parser-merged"

def bytes_to_unicode():
    bs = list(range(ord('!'), ord('~') + 1)) + list(range(ord('¡'), ord('¬') + 1)) + list(range(ord('®'), ord('ÿ') + 1))
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b)
            cs.append(256 + n)
            n += 1
    return {b: chr(c) for b, c in zip(bs, cs)}

def run_parity_test():
    print("=" * 60)
    print(" Testing Qwen2.5 Byte-Level BPE Tokenizer Parity")
    print("=" * 60)

    from transformers import AutoTokenizer
    hf_tokenizer = AutoTokenizer.from_pretrained(str(MODEL_DIR))

    byte_encoder = bytes_to_unicode()

    with open(MODEL_DIR / "vocab.json", "r", encoding="utf-8") as f:
        vocab = json.load(f)

    with open(MODEL_DIR / "merges.txt", "r", encoding="utf-8") as f:
        merges_lines = [l.strip().split() for l in f if l.strip() and not l.startswith("#")]

    bpe_ranks = {tuple(m): i for i, m in enumerate(merges_lines)}

    pat = regex.compile(r"""(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+""")

    def get_pairs(word):
        pairs = set()
        prev_char = word[0]
        for char in word[1:]:
            pairs.add((prev_char, char))
            prev_char = char
        return pairs

    def bpe(token):
        word = tuple(token)
        pairs = get_pairs(word)
        if not pairs:
            return [token]
        while True:
            min_pair = min(pairs, key=lambda pair: bpe_ranks.get(pair, float("inf")))
            if min_pair not in bpe_ranks:
                break
            first, second = min_pair
            new_word = []
            i = 0
            while i < len(word):
                try:
                    j = word.index(first, i)
                    new_word.extend(word[i:j])
                    i = j
                except ValueError:
                    new_word.extend(word[i:])
                    break
                if word[i] == first and i < len(word) - 1 and word[i+1] == second:
                    new_word.append(first + second)
                    i += 2
                else:
                    new_word.append(word[i])
                    i += 1
            word = tuple(new_word)
            if len(word) == 1:
                break
            pairs = get_pairs(word)
        return list(word)

    def custom_encode(text):
        tokens = []
        for match in pat.finditer(text):
            piece = match.group()
            bpe_tokens = "".join(byte_encoder[b] for b in piece.encode("utf-8"))
            merged = bpe(bpe_tokens)
            for t in merged:
                if t in vocab:
                    tokens.append(vocab[t])
                else:
                    print("MISSING TOKEN:", repr(t))
        return tokens

    test_samples = [
        "Project: Grease",
        "Role: Sandy",
        "Casting: Mukesh Chhabra Casting Company (MCCC)",
        "Due: 5 NOVEMBER 2026",
        '{"project": "Escape Plan", "role": "Male Actor (20-40 years)"}',
        "ACT ONE SCENE SIX\nSANDY:\nDo a split, give a yell!",
        "INT. AUDITION ROOM - DAY\nMAYA\n(looking straight at lens)\nI can do this.",
        "Special chars & parentheticals: [HAMLET] (leaning close, whispering) To be or not to be.",
        "Tabular grid:\nRole | Age | Location\nHero | 25-35 | Mumbai",
    ]

    all_passed = True
    for idx, sample in enumerate(test_samples):
        expected = hf_tokenizer.encode(sample)
        actual = custom_encode(sample)
        match = (expected == actual)
        status = "[PASS]" if match else "[FAIL]"
        print(f" {status} Sample {idx+1}: {repr(sample[:35])} ({len(expected)} tokens)")
        if not match:
            print(f"   Expected: {expected}")
            print(f"   Actual:   {actual}")
            all_passed = False

    print("=" * 60)
    if all_passed:
        print(" All Tokenizer Parity Tests PASSED with 100.0% Exact Match!")
    else:
        print(" Tokenizer Parity FAILED! Check mismatched token IDs above.")
    print("=" * 60)
    return all_passed

if __name__ == "__main__":
    success = run_parity_test()
    sys.exit(0 if success else 1)
