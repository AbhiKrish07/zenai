"""
SCTM Integration Demo & Test Harness
=====================================
Demonstrates all public API methods with realistic conversational data.
Run with: python sctm_demo.py
"""

import time
import json
from sctm_module import SCTM_Module


def banner(title: str) -> None:
    print(f"\n{'═'*60}")
    print(f"  {title}")
    print(f"{'═'*60}")


def pp(obj) -> None:
    """Pretty-print a dict or list."""
    print(json.dumps(obj, indent=2, default=str))


# ══════════════════════════════════════════════════════════════════
#  INSTANTIATE
# ══════════════════════════════════════════════════════════════════

banner("1. Initialising SCTM Module")
mem = SCTM_Module(
    model_name       = "all-MiniLM-L6-v2",   # 384-dim, fast on CPU
    alpha            = 0.50,   # semantic weight
    beta             = 0.30,   # temporal decay weight
    gamma            = 0.20,   # reinforcement weight
    decay_lambda     = 0.10,   # e-fold time ≈ 10 days
    reinforce_kappa  = 5.0,    # half-saturation at 5 recalls
    prune_threshold  = 0.20,   # discard below 20% confidence
    ivf_train_threshold = 256, # upgrade to IVF at 256 memories
    nprobe           = 4,      # ANN accuracy vs speed trade-off
)
print(f"Memory bank size: {mem.size}")


# ══════════════════════════════════════════════════════════════════
#  STORE MEMORIES
# ══════════════════════════════════════════════════════════════════

banner("2. Storing Memories")

ids = []
corpus = [
    ("My favourite programming language is Python.",                        {"category": "preference", "source": "chat"}),
    ("I have a PhD interview at MIT on 24th March 2026.",                  {"category": "event",      "source": "calendar"}),
    ("The user is building a Jarvis-like AI assistant called B.L.I.T.Z.",  {"category": "project",    "source": "onboarding"}),
    ("My workout schedule is Monday, Wednesday, Friday — upper body.",      {"category": "health",     "source": "chat"}),
    ("I am vegetarian and allergic to peanuts.",                           {"category": "health",     "source": "profile"}),
    ("Goal for 2026: raise a $500K seed round for my startup.",            {"category": "goal",       "source": "journal"}),
    ("I prefer dark mode and brutalist UI design aesthetics.",             {"category": "preference", "source": "chat"}),
    ("My study streak broke last Tuesday because of a power cut.",         {"category": "reflection", "source": "journal"}),
    ("Groq API key is gsk_... (redacted for safety).",                     {"category": "credential", "source": "settings"}),
    ("Vector databases are useful for semantic memory retrieval.",         {"category": "knowledge",  "source": "research"}),
]

for text, meta in corpus:
    mid = mem.store_memory(text, metadata=meta)
    ids.append(mid)
    print(f"  ✓ Stored [{mid[:8]}…] → {text[:55]}…")

print(f"\nBank size after storing: {mem.size}")


# ══════════════════════════════════════════════════════════════════
#  RETRIEVE — NORMAL QUERY
# ══════════════════════════════════════════════════════════════════

banner("3. Retrieve — Normal Query")
results = mem.retrieve_memory(
    query="What are the user's health preferences?",
    top_k=5,
    confidence_threshold=0.25,
)
print(f"Results ({len(results)} found):")
pp(results)


# ══════════════════════════════════════════════════════════════════
#  RETRIEVE — HIGH THRESHOLD (selective)
# ══════════════════════════════════════════════════════════════════

banner("4. Retrieve — High Confidence Threshold (0.70)")
results_strict = mem.retrieve_memory(
    query="What programming tools does the user prefer?",
    top_k=5,
    confidence_threshold=0.70,
)
print(f"Results with threshold=0.70: ({len(results_strict)} passed)")
pp(results_strict)


# ══════════════════════════════════════════════════════════════════
#  EDGE CASE: EMPTY BANK
# ══════════════════════════════════════════════════════════════════

banner("5. Edge Case — Empty Bank")
empty_mem = SCTM_Module()
result_empty = empty_mem.retrieve_memory("Tell me about AI assistants.")
print(f"Empty bank result: {result_empty!r}")  # Should be []


# ══════════════════════════════════════════════════════════════════
#  EDGE CASE: EMPTY STORE
# ══════════════════════════════════════════════════════════════════

banner("6. Edge Case — Empty Text Store")
try:
    mem.store_memory("   ")   # whitespace-only
except ValueError as e:
    print(f"Caught expected error: {e}")


# ══════════════════════════════════════════════════════════════════
#  CONFIDENCE SCORE DECOMPOSITION
# ══════════════════════════════════════════════════════════════════

banner("7. Confidence Score Decomposition")

import math

trace = list(mem._bank.values())[0]
print(f"Memory: '{trace.text[:55]}…'")
print(f"  recall_count:     {trace.recall_count}")
print(f"  created_at:       {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(trace.created_at))}")
print(f"  last_recalled_at: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(trace.last_recalled_at))}")

delta_days = (time.time() - trace.last_recalled_at) / 86_400
decay      = math.exp(-mem.decay_lambda * delta_days)
reinforce  = math.tanh(trace.recall_count / mem.reinforce_kappa)
sim        = 0.85   # hypothetical query similarity

confidence = mem.alpha * sim + mem.beta * decay + mem.gamma * reinforce
print(f"\n  α={mem.alpha} · sim={sim:.2f}         = {mem.alpha * sim:.4f}")
print(f"  β={mem.beta} · decay={decay:.4f}       = {mem.beta * decay:.4f}  (Δt={delta_days:.4f} days)")
print(f"  γ={mem.gamma} · reinforce={reinforce:.4f} = {mem.gamma * reinforce:.4f}")
print(f"  ─────────────────────────────────────")
print(f"  C = {confidence:.4f}")


# ══════════════════════════════════════════════════════════════════
#  DELETE
# ══════════════════════════════════════════════════════════════════

banner("8. Delete a Memory")
target_id = ids[2]
print(f"Deleting id={target_id[:8]}…")
success = mem.delete_memory(target_id)
print(f"Deleted: {success} | New bank size: {mem.size}")

# Confirm it's gone
results_after_delete = mem.retrieve_memory(
    "B.L.I.T.Z. AI assistant project",
    confidence_threshold=0.25,
)
print(f"Results for deleted query after removal: {len(results_after_delete)}")


# ══════════════════════════════════════════════════════════════════
#  SUMMARY STATS
# ══════════════════════════════════════════════════════════════════

banner("9. Memory Bank Summary")
pp(mem.summary())


# ══════════════════════════════════════════════════════════════════
#  CONSOLIDATION
# ══════════════════════════════════════════════════════════════════

banner("10. Consolidate (Prune + Merge)")
report = mem.consolidate(similarity_merge_threshold=0.92)
print(f"Consolidation report:")
pp(report)
print(f"\nFinal bank size: {mem.size}")
pp(mem.summary())
