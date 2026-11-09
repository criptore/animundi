#!/usr/bin/env bash
# Ships the built-in mind's model with an exported game, so players don't download it on first
# launch: copies (or downloads) the GGUF file into models/ next to the exported executable.
#   tools/bundle_model.sh <export folder> [model.gguf]
# Without a model file, the default one (Qwen2.5 0.5B Instruct Q4_K_M, Apache 2.0) is downloaded.
set -euo pipefail
dest="${1:?usage: tools/bundle_model.sh <export folder> [model.gguf]}"
file="${2:-}"
mkdir -p "$dest/models"
if [ -n "$file" ]; then
	cp "$file" "$dest/models/"
else
	curl -L --fail -o "$dest/models/qwen2.5-0.5b-instruct-q4_k_m.gguf" \
		"https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
fi
ls -la "$dest/models"
