# G7 experimental evidence-grounded integration

This is an operational, non-normative experiment. It does not reconstruct
AETHERIS_AI, define a global model identity, or make llama.cpp authoritative.

The fixture suite in `tests/g7-experimental-evidence-suite.py` preserves the
three validation layers:

1. evidence identity and provenance validation;
2. interpretation structure and evidence-use validation;
3. explicit `NON_AUTHORITATIVE` LLM interpretation.

Retrieved document text is untrusted data, never a control channel. A
`CitationSpan` identifies evidence; it does not authorize instructions.
Scientific evidence, model inference, Knowledge evidence, and LLM
interpretation remain separate in the experimental bundle schema.

The deterministic stub covers supported, insufficient, conflicting,
irrelevant, prompt-injection, malformed-output, unknown-reference, duplicate,
and provenance-mismatch cases. It is not a substitute for the unavailable
canonical AETHERIS_AI implementation and does not reproduce the Qwen runtime.

The manual Jetson results remain experimental evidence: llama.cpp/CUDA
execution passed, while ungrounded RF factuality failed and general grounding
robustness remains unhomologated. The observed unsupported EME decoration and
the fail-safe structured abstention are retained as findings, not converted
into universal model claims.

## Boundary status

No verified public versioned RF-to-Knowledge-to-AI contract was found in the
available repositories. The fixture is therefore a provisional integration
projection only. It must not be promoted to a shared normative contract
without Governance authority and recovery of AETHERIS_AI source.
