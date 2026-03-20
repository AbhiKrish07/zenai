"""
╔══════════════════════════════════════════════════════════════════════════╗
║     Sparse Confident Tensor Memory (SCTM) — Core Implementation         ║
║     Author: B.L.I.T.Z. Research Engineering                              ║
║     Version: 1.0.0                                                       ║
╠══════════════════════════════════════════════════════════════════════════╣
║  Architecture:                                                           ║
║    Tensor Representation  →  SentenceTransformers (MiniLM-L6-v2)        ║
║    Sparse Retrieval       →  FAISS IVF index (ANN, O(log n))            ║
║    Confidence Scoring     →  C = αSim + βDecay + γReinforce             ║
║    Memory Consolidation   →  Threshold-based pruning + cluster merge     ║
╚══════════════════════════════════════════════════════════════════════════╝

Dependencies:
    pip install torch numpy faiss-cpu sentence-transformers
"""

from __future__ import annotations

import time
import math
import uuid
import logging
from dataclasses import dataclass, field
from typing import Any, Optional

import numpy as np
import torch
import torch.nn.functional as F
import faiss
from sentence_transformers import SentenceTransformer

# ── Logging ────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [SCTM] %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("SCTM")


# ══════════════════════════════════════════════════════════════════════════
#  DATA STRUCTURES
# ══════════════════════════════════════════════════════════════════════════

@dataclass
class MemoryTrace:
    """
    A single memory unit stored in the SCTM bank.

    Attributes
    ----------
    id : str
        Globally unique identifier (UUID4).
    text : str
        Original natural-language text of the memory.
    embedding : np.ndarray
        High-dimensional float32 tensor (shape: [dim]).
    metadata : dict
        Arbitrary user-supplied metadata (e.g., source, category, tags).
    created_at : float
        Unix timestamp of when the memory was formed.
    last_recalled_at : float
        Unix timestamp of the most recent retrieval.
    recall_count : int
        Number of times this memory has been retrieved (reinforcement signal).
    confidence : float
        Last computed confidence score C ∈ [0, 1].
    """
    id: str
    text: str
    embedding: np.ndarray
    metadata: dict = field(default_factory=dict)
    created_at: float = field(default_factory=time.time)
    last_recalled_at: float = field(default_factory=time.time)
    recall_count: int = 0
    confidence: float = 1.0


# ══════════════════════════════════════════════════════════════════════════
#  SCTM MODULE
# ══════════════════════════════════════════════════════════════════════════

class SCTM_Module:
    """
    Sparse Confident Tensor Memory (SCTM)
    ======================================
    A high-dimensional, sparse, confidence-weighted long-term memory
    system for personal AI assistants.

    Core pillars
    ------------
    1. **Tensor Representation** — SentenceTransformer encodes text into
       dense float32 embeddings stored as PyTorch tensors internally.

    2. **Sparse Retrieval** — FAISS IVFFlat (Inverted File Index) with
       Approximate Nearest Neighbour search; O(log n) retrieval vs O(n)
       for brute-force. Falls back to FlatL2 when < `ivf_train_threshold`
       memories exist (FAISS IVF requires training data).

    3. **Confidence Scoring** — Each retrieved memory receives a score
       computed from three orthogonal signals:

           C = α·sim + β·decay + γ·reinforce

       where:
           sim       = cosine similarity ∈ [0, 1]
           decay     = exp(−λ · Δt_days)              (temporal decay)
           reinforce = tanh(recall_count / κ)          (Hebbian reinforcement)
           α + β + γ = 1.0                             (normalised weights)

    4. **Pruning & Consolidation** — `consolidate()` removes memories
       whose rolling confidence drops below `prune_threshold`, and
       optionally merges highly similar memory clusters.

    Parameters
    ----------
    model_name : str
        HuggingFace SentenceTransformer model to use for embeddings.
        Default: 'all-MiniLM-L6-v2' (384-dim, ~22 MB, very fast CPU).
    alpha : float
        Weight for semantic similarity in confidence score (default 0.5).
    beta : float
        Weight for temporal decay (default 0.3).
    gamma : float
        Weight for reinforcement (default 0.2).
    decay_lambda : float
        Decay rate λ in exp(−λ·Δt_days). Higher → memories fade faster.
        Default 0.1 (half-life ≈ 7 days).
    reinforce_kappa : float
        Softening constant κ in tanh(recall/κ). Higher → reinforcement
        saturates more slowly. Default 5.
    prune_threshold : float
        Memories with C < prune_threshold are removed during consolidation.
    ivf_train_threshold : int
        Minimum memories required before switching to IVF index.
        Below this, a flat brute-force index is used (correct & safe).
    nlist : int
        Number of Voronoi cells for the IVF index. Larger → more accurate
        but slower. Typical: sqrt(N).
    nprobe : int
        Cells visited during ANN search. Trade-off: accuracy vs speed.
    device : str
        'cpu' or 'cuda'. Embedding model is moved there automatically.
    """

    def __init__(
        self,
        model_name: str = "all-MiniLM-L6-v2",
        alpha: float = 0.50,
        beta: float = 0.30,
        gamma: float = 0.20,
        decay_lambda: float = 0.10,
        reinforce_kappa: float = 5.0,
        prune_threshold: float = 0.20,
        ivf_train_threshold: int = 256,
        nlist: int = 16,
        nprobe: int = 4,
        device: str = "cpu",
    ):
        # ── Validate weights ────────────────────────────────────────────
        total = alpha + beta + gamma
        if not math.isclose(total, 1.0, abs_tol=1e-4):
            raise ValueError(
                f"Confidence weights α+β+γ must sum to 1.0 (got {total:.4f}). "
                "Adjust alpha/beta/gamma."
            )

        # ── Hyperparameters ──────────────────────────────────────────────
        self.alpha = alpha
        self.beta = beta
        self.gamma = gamma
        self.decay_lambda = decay_lambda
        self.reinforce_kappa = reinforce_kappa
        self.prune_threshold = prune_threshold
        self.ivf_train_threshold = ivf_train_threshold
        self.nlist = nlist
        self.nprobe = nprobe
        self.device = device

        # ── Embedding model ──────────────────────────────────────────────
        logger.info(f"Loading embedding model '{model_name}' on {device}…")
        self._encoder = SentenceTransformer(model_name, device=device)
        self.dim: int = self._encoder.get_sentence_embedding_dimension()
        logger.info(f"Embedding dimension: {self.dim}")

        # ── Memory bank ──────────────────────────────────────────────────
        # id_list[i] maps FAISS internal index i → memory id
        self._bank: dict[str, MemoryTrace] = {}   # id → MemoryTrace
        self._id_list: list[str] = []             # positional index → id
        self._faiss_index: faiss.Index = self._build_flat_index()
        self._use_ivf: bool = False

        logger.info("SCTM Module initialised. Memory bank is empty.")

    # ══════════════════════════════════════════════════════════════════
    #  PUBLIC API
    # ══════════════════════════════════════════════════════════════════

    def store_memory(self, text: str, metadata: Optional[dict] = None) -> str:
        """
        Encode `text` into a tensor embedding and store it in the memory bank.

        The embedding is normalised to unit length (L2) before storage so
        that inner-product search is equivalent to cosine similarity.

        Parameters
        ----------
        text : str
            Natural-language string to store. Must be non-empty.
        metadata : dict, optional
            Arbitrary key-value metadata (e.g., {'source': 'chat', 'tag': 'goal'}).

        Returns
        -------
        str
            The UUID4 id of the newly stored MemoryTrace.

        Raises
        ------
        ValueError
            If `text` is empty or whitespace-only.
        """
        if not text or not text.strip():
            raise ValueError("Cannot store an empty memory. `text` must be non-empty.")

        metadata = metadata or {}
        mem_id = str(uuid.uuid4())

        # ── Embed & normalise ────────────────────────────────────────────
        with torch.no_grad():
            raw: np.ndarray = self._encoder.encode(
                text.strip(),
                convert_to_numpy=True,
                normalize_embeddings=True,   # unit-norm for cosine via dot-product
                show_progress_bar=False,
            ).astype(np.float32)

        embedding = raw.reshape(1, self.dim)   # FAISS expects shape (1, dim)

        # ── Create trace ─────────────────────────────────────────────────
        trace = MemoryTrace(
            id=mem_id,
            text=text.strip(),
            embedding=raw,
            metadata=metadata,
        )
        self._bank[mem_id] = trace
        self._id_list.append(mem_id)

        # ── Update FAISS index ───────────────────────────────────────────
        self._maybe_upgrade_index()
        self._faiss_index.add(embedding)

        logger.info(f"[STORE] id={mem_id[:8]}… | bank_size={len(self._bank)}")
        return mem_id

    def retrieve_memory(
        self,
        query: str,
        top_k: int = 5,
        confidence_threshold: float = 0.30,
    ) -> list[dict[str, Any]]:
        """
        Retrieve the most relevant memories for `query` using sparse ANN
        search, then rank by composite confidence score.

        Parameters
        ----------
        query : str
            Natural-language query string.
        top_k : int
            Maximum number of candidates to fetch from the FAISS index
            before confidence filtering. Default 5.
        confidence_threshold : float
            Minimum C score ∈ [0, 1] for a memory to be returned.
            Memories below this are silently discarded. Default 0.30.

        Returns
        -------
        list[dict]
            Sorted list of result dicts (highest confidence first):
            {
                'id': str,
                'text': str,
                'metadata': dict,
                'confidence': float,        # composite C score
                'similarity': float,        # raw cosine similarity
                'recall_count': int,
                'created_at': float,
            }

        Edge Cases
        ----------
        - Empty bank → returns [] immediately.
        - Empty query → raises ValueError.
        - top_k > bank_size → clamped to bank_size automatically.
        """
        if not query or not query.strip():
            raise ValueError("Query must be a non-empty string.")

        # ── Edge case: empty memory bank ─────────────────────────────────
        if not self._bank:
            logger.warning("[RETRIEVE] Memory bank is empty. Returning [].")
            return []

        k = min(top_k, len(self._bank))

        # ── Embed query ──────────────────────────────────────────────────
        with torch.no_grad():
            q_vec: np.ndarray = self._encoder.encode(
                query.strip(),
                convert_to_numpy=True,
                normalize_embeddings=True,
                show_progress_bar=False,
            ).astype(np.float32).reshape(1, self.dim)

        # ── Sparse ANN search (FAISS) ────────────────────────────────────
        if hasattr(self._faiss_index, "nprobe"):
            self._faiss_index.nprobe = self.nprobe

        distances, indices = self._faiss_index.search(q_vec, k)
        # distances = cosine distances (since embeddings are unit-normalised,
        #   inner product == cosine similarity; FAISS IP returns similarity directly
        #   for IndexFlatIP, but IVFFlat with L2 needs conversion — see below)

        # ── Build results with confidence scores ─────────────────────────
        results = []
        for rank, (dist, idx) in enumerate(zip(distances[0], indices[0])):
            if idx < 0 or idx >= len(self._id_list):
                continue   # FAISS may return -1 for empty slots

            mem_id = self._id_list[idx]
            trace = self._bank.get(mem_id)
            if trace is None:
                continue

            # Convert L2 distance → cosine similarity
            # For unit-norm vectors: cosine_sim = 1 - L2²/2
            cosine_sim = float(np.clip(1.0 - (dist / 2.0), 0.0, 1.0))

            confidence = self._calculate_confidence(
                trace=trace,
                cosine_similarity=cosine_sim,
            )

            if confidence < confidence_threshold:
                continue

            # ── Update recall statistics ────────────────────────────────
            trace.recall_count += 1
            trace.last_recalled_at = time.time()
            trace.confidence = confidence

            results.append({
                "id": trace.id,
                "text": trace.text,
                "metadata": trace.metadata,
                "confidence": round(confidence, 4),
                "similarity": round(cosine_sim, 4),
                "recall_count": trace.recall_count,
                "created_at": trace.created_at,
            })

        # ── Sort by confidence descending ────────────────────────────────
        results.sort(key=lambda r: r["confidence"], reverse=True)

        logger.info(
            f"[RETRIEVE] query='{query[:40]}…' | "
            f"candidates={k} | passed_threshold={len(results)}"
        )
        return results

    def consolidate(
        self,
        similarity_merge_threshold: float = 0.95,
    ) -> dict[str, int]:
        """
        Memory consolidation pass — two-stage:

        Stage 1 — Prune:
            Recompute each memory's intrinsic confidence (with similarity=1.0
            as the upper-bound baseline) and drop any that fall below
            `self.prune_threshold`.

        Stage 2 — Merge (optional deduplication):
            Detect pairs of memories whose cosine similarity exceeds
            `similarity_merge_threshold` and merge them into a single trace
            (keeping the one with the higher recall_count).

        Returns
        -------
        dict
            {'pruned': int, 'merged': int, 'remaining': int}
        """
        if not self._bank:
            logger.info("[CONSOLIDATE] Bank is empty. Nothing to do.")
            return {"pruned": 0, "merged": 0, "remaining": 0}

        logger.info(f"[CONSOLIDATE] Starting. Bank size = {len(self._bank)}")

        # ── Stage 1: Prune ───────────────────────────────────────────────
        pruned_ids: list[str] = []
        for mem_id, trace in list(self._bank.items()):
            # Use sim=1.0 as max possible baseline for intrinsic score
            score = self._calculate_confidence(trace=trace, cosine_similarity=1.0)
            if score < self.prune_threshold:
                pruned_ids.append(mem_id)

        for mem_id in pruned_ids:
            del self._bank[mem_id]

        pruned_count = len(pruned_ids)
        logger.info(f"[CONSOLIDATE] Pruned {pruned_count} low-confidence traces.")

        # ── Stage 2: Merge near-duplicates ───────────────────────────────
        merged_count = 0
        ids = list(self._bank.keys())

        # Build a temporary dense matrix for pairwise similarity
        if len(ids) > 1:
            vecs = np.stack(
                [self._bank[i].embedding for i in ids], axis=0
            ).astype(np.float32)
            # Cosine similarity matrix (unit-norm → dot product)
            sim_matrix: np.ndarray = vecs @ vecs.T  # shape [N, N]

            to_remove: set[str] = set()
            for i in range(len(ids)):
                if ids[i] in to_remove:
                    continue
                for j in range(i + 1, len(ids)):
                    if ids[j] in to_remove:
                        continue
                    if sim_matrix[i, j] >= similarity_merge_threshold:
                        # Keep the one with more recalls; drop the other
                        keep, drop = (
                            (ids[i], ids[j])
                            if self._bank[ids[i]].recall_count
                            >= self._bank[ids[j]].recall_count
                            else (ids[j], ids[i])
                        )
                        # Accumulate recall counts before merging
                        self._bank[keep].recall_count += self._bank[drop].recall_count
                        to_remove.add(drop)
                        merged_count += 1
                        logger.debug(
                            f"[CONSOLIDATE] Merging {drop[:8]}… → {keep[:8]}… "
                            f"(sim={sim_matrix[i,j]:.3f})"
                        )

            for mid in to_remove:
                if mid in self._bank:
                    del self._bank[mid]

        # ── Rebuild FAISS index from remaining memories ──────────────────
        self._rebuild_index()

        remaining = len(self._bank)
        logger.info(
            f"[CONSOLIDATE] Done. Pruned={pruned_count} | "
            f"Merged={merged_count} | Remaining={remaining}"
        )
        return {"pruned": pruned_count, "merged": merged_count, "remaining": remaining}

    def delete_memory(self, mem_id: str) -> bool:
        """
        Delete a specific memory by id.

        Returns True if found and deleted, False if not found.
        Note: FAISS does not support ID-based deletion natively;
        the index is rebuilt after removal.
        """
        if mem_id not in self._bank:
            logger.warning(f"[DELETE] id={mem_id[:8]}… not found.")
            return False

        del self._bank[mem_id]
        self._rebuild_index()
        logger.info(f"[DELETE] id={mem_id[:8]}… removed. Remaining={len(self._bank)}")
        return True

    @property
    def size(self) -> int:
        """Number of memories currently in the bank."""
        return len(self._bank)

    def summary(self) -> dict[str, Any]:
        """Return a statistics snapshot of the memory bank."""
        if not self._bank:
            return {"size": 0, "avg_confidence": 0.0, "avg_recall": 0.0}

        confidences = [t.confidence for t in self._bank.values()]
        recalls = [t.recall_count for t in self._bank.values()]
        return {
            "size": len(self._bank),
            "avg_confidence": round(float(np.mean(confidences)), 4),
            "max_confidence": round(float(np.max(confidences)), 4),
            "min_confidence": round(float(np.min(confidences)), 4),
            "avg_recall": round(float(np.mean(recalls)), 2),
            "index_type": "IVFFlat" if self._use_ivf else "FlatL2",
            "embedding_dim": self.dim,
        }

    # ══════════════════════════════════════════════════════════════════
    #  INTERNAL METHODS
    # ══════════════════════════════════════════════════════════════════

    def _calculate_confidence(
        self,
        trace: MemoryTrace,
        cosine_similarity: float,
    ) -> float:
        """
        Compute the composite confidence score C ∈ [0, 1].

        Formula
        -------
            C = α·sim + β·decay + γ·reinforce

        Components
        ----------
        sim : float
            Cosine similarity between query and memory embeddings, ∈ [0, 1].
            Already unit-normalised, so dot product = cosine sim.

        decay : float
            Temporal decay modelled as exponential:
                decay = exp(−λ · Δt_days)
            where Δt_days = days elapsed since memory was last recalled.
            - At Δt=0 → decay=1.0 (just recalled / brand-new)
            - At Δt=7 (λ=0.1)  → decay ≈ 0.50
            - At Δt=30 (λ=0.1) → decay ≈ 0.05

        reinforce : float
            Hebbian-style reinforcement:
                reinforce = tanh(recall_count / κ)
            Saturates toward 1.0 as recall frequency grows.
            - recall=0  → reinforce=0.0
            - recall=κ  → reinforce≈0.76
            - recall=2κ → reinforce≈0.96

        Parameters
        ----------
        trace : MemoryTrace
            The memory to score.
        cosine_similarity : float
            Precomputed cosine similarity from the retrieval step.

        Returns
        -------
        float
            Confidence score C ∈ [0, 1].
        """
        # ── Semantic similarity ──────────────────────────────────────────
        sim = float(np.clip(cosine_similarity, 0.0, 1.0))

        # ── Temporal decay ───────────────────────────────────────────────
        now = time.time()
        delta_seconds = now - trace.last_recalled_at
        delta_days = delta_seconds / 86_400.0          # 86400 s/day
        decay = math.exp(-self.decay_lambda * delta_days)

        # ── Reinforcement ────────────────────────────────────────────────
        reinforce = math.tanh(trace.recall_count / self.reinforce_kappa)

        # ── Composite score ──────────────────────────────────────────────
        confidence = (
            self.alpha * sim
            + self.beta  * decay
            + self.gamma * reinforce
        )
        return float(np.clip(confidence, 0.0, 1.0))

    def _build_flat_index(self) -> faiss.Index:
        """Build a small, exact FlatL2 FAISS index (safe for small banks)."""
        index = faiss.IndexFlatL2(self.dim)
        return index

    def _build_ivf_index(self, embeddings: np.ndarray) -> faiss.Index:
        """
        Build and train an IVFFlat FAISS index for approximate nearest-
        neighbour search. Dramatically faster than flat search at scale.

        The quantiser is a flat L2 index used to assign vectors to
        Voronoi cells (nlist cells total).
        """
        quantiser = faiss.IndexFlatL2(self.dim)
        index = faiss.IndexIVFFlat(quantiser, self.dim, self.nlist, faiss.METRIC_L2)
        assert index.is_trained is False
        index.train(embeddings)
        index.add(embeddings)
        return index

    def _maybe_upgrade_index(self) -> None:
        """
        Upgrade from FlatL2 → IVFFlat once we have enough memories to
        justify the overhead. Called after every store operation.
        """
        n = len(self._bank)
        if not self._use_ivf and n >= self.ivf_train_threshold:
            logger.info(
                f"[INDEX] Upgrading to IVFFlat (nlist={self.nlist}) "
                f"at bank_size={n}"
            )
            self._rebuild_index()

    def _rebuild_index(self) -> None:
        """
        Reconstruct the FAISS index from scratch using the current bank.
        Called after deletions, merges, and index upgrades.
        """
        self._id_list = list(self._bank.keys())

        if not self._id_list:
            self._faiss_index = self._build_flat_index()
            self._use_ivf = False
            return

        embeddings = np.stack(
            [self._bank[mid].embedding for mid in self._id_list],
            axis=0,
        ).astype(np.float32)

        if len(self._id_list) >= self.ivf_train_threshold:
            self._faiss_index = self._build_ivf_index(embeddings)
            self._use_ivf = True
        else:
            self._faiss_index = self._build_flat_index()
            self._faiss_index.add(embeddings)
            self._use_ivf = False

        logger.debug(
            f"[INDEX] Rebuilt {'IVFFlat' if self._use_ivf else 'FlatL2'} "
            f"with {len(self._id_list)} vectors."
        )
