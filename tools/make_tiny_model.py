"""A tiny random llama-architecture GGUF (110 KB) with a byte-level tokenizer, to test the
built-in mind's pipeline (loading llama.cpp, grammar-constrained sampling, validation) without a
real model. It writes nonsense, but the grammar keeps it inside the invention language.
    python3 tools/make_tiny_model.py tests/data/tiny_random.gguf   (needs: pip install gguf numpy)"""
import sys
import numpy as np
import gguf

out = sys.argv[1]
rng = np.random.default_rng(1)
# GPT-2 byte-level vocabulary: the 256 byte symbols, plus specials.
bs = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + list(range(ord("®"), ord("ÿ") + 1))
cs = bs[:]
n = 0
for b in range(256):
    if b not in bs:
        bs.append(b)
        cs.append(256 + n)
        n += 1
byte_tokens = [chr(c) for c in cs]
tokens = byte_tokens + ["\u0120t", "\u0120a"] + ["<|endoftext|>", "<|im_start|>", "<|im_end|>"]
types = [gguf.TokenType.NORMAL] * 258 + [gguf.TokenType.CONTROL] * 3
V, E, L, H, F = len(tokens), 32, 1, 2, 64

w = gguf.GGUFWriter(out, "llama")
w.add_name("tiny-test")
w.add_context_length(512)
w.add_embedding_length(E)
w.add_block_count(L)
w.add_feed_forward_length(F)
w.add_head_count(H)
w.add_head_count_kv(H)
w.add_rope_dimension_count(E // H)
w.add_layer_norm_rms_eps(1e-5)
w.add_file_type(0)
w.add_tokenizer_model("gpt2")
w.add_tokenizer_pre("default")
w.add_token_list(tokens)
w.add_token_types(types)
w.add_token_merges(["\u0120 t", "\u0120 a"])
w.add_bos_token_id(258)
w.add_eos_token_id(258)

def t(name, *shape):
    w.add_tensor(name, (rng.standard_normal(shape) * 0.02).astype(np.float32))

t("token_embd.weight", V, E)
w.add_tensor("output_norm.weight", np.ones(E, dtype=np.float32))
t("output.weight", V, E)
for i in range(L):
    w.add_tensor(f"blk.{i}.attn_norm.weight", np.ones(E, dtype=np.float32))
    t(f"blk.{i}.attn_q.weight", E, E)
    t(f"blk.{i}.attn_k.weight", E, E)
    t(f"blk.{i}.attn_v.weight", E, E)
    t(f"blk.{i}.attn_output.weight", E, E)
    w.add_tensor(f"blk.{i}.ffn_norm.weight", np.ones(E, dtype=np.float32))
    t(f"blk.{i}.ffn_gate.weight", F, E)
    t(f"blk.{i}.ffn_up.weight", F, E)
    t(f"blk.{i}.ffn_down.weight", E, F)
w.write_header_to_file()
w.write_kv_data_to_file()
w.write_tensors_to_file()
w.close()
print("wrote", out, V, "tokens")
