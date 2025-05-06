from flask import Flask, request, jsonify
import requests
import re
import time
from difflib import get_close_matches

app = Flask(__name__)

# Endpoints
OLLAMA_URL      = "http://localhost:11434/api/generate"
MIMIR_QUERY     = "http://localhost:9009/prometheus/api/v1/query"
MIMIR_LABEL_URL = "http://localhost:9009/prometheus/api/v1/label/{label}/values"
OLLAMA_MODEL    = "mistral"
LABEL_CACHE_TTL = 600  # seconds

# Simple explicit fallbacks
FALLBACK_MAP = {
    "show node exporter instance": 'up{job="node"}',
}

# In-memory cache for labels
label_cache = {}  # e.g. {"__name__": {"data":[...], "ts":...}}

def fetch_label(label: str) -> list:
    """Fetch and cache label values from Mimir."""
    now = time.time()
    entry = label_cache.get(label)
    if entry and now - entry["ts"] < LABEL_CACHE_TTL:
        return entry["data"]
    try:
        r = requests.get(MIMIR_LABEL_URL.format(label=label), timeout=5)
        r.raise_for_status()
        vals = r.json().get("data", [])
    except:
        vals = []
    label_cache[label] = {"data": vals, "ts": now}
    return vals

def is_available_metrics_query(p: str) -> bool:
    return "available metrics" in p.lower() or "list metrics" in p.lower()

def handle_available_metrics(prompt: str) -> str:
    names = fetch_label("__name__")
    m = re.search(r"metrics\s+for\s+(\w+)", prompt.lower())
    if m:
        keyword = m.group(1)
        filtered = [n for n in names if keyword in n.lower()]
        if filtered:
            names = filtered
        else:
            return (
                f"⚠️ No metrics found containing “{keyword}”.\n"
                f"Suggestions:\n{suggest_metrics(keyword, names)}"
            )
    if not names:
        return "⚠️ No metrics available."
    lines = [" · ".join(names[i : i + 5]) for i in range(0, len(names), 5)]
    return "\n".join(lines)

def extract_promql(text: str) -> str | None:
    for line in text.splitlines():
        l = line.strip(" `")
        if "{" in l and "}" in l:
            return l
    return None

def generate_promql(prompt: str) -> str | None:
    fb = FALLBACK_MAP.get(prompt.lower().strip())
    if fb:
        return fb

    # Provide real label hints to the LLM
    jobs = fetch_label("job")
    inst = fetch_label("instance")
    hint = f"Jobs: {', '.join(jobs)}\nInstances: {', '.join(inst)}\n"

    payload = {
        "model": OLLAMA_MODEL,
        "prompt": hint
                  + "Respond with exactly one valid PromQL query (no markdown, no explanation): "
                  + prompt,
        "stream": False
    }
    try:
        r = requests.post(OLLAMA_URL, json=payload, timeout=10)
        r.raise_for_status()
        return extract_promql(r.json().get("response", ""))
    except:
        return None

def suggest_metrics(term: str, choices: list[str]) -> str:
    matches = get_close_matches(term, choices, n=5, cutoff=0.4)
    if not matches:
        return "  (no similar metrics)"
    return "\n".join(f"  • {m}" for m in matches)

def fallback_keyword_host(prompt: str) -> str | None:
    """
    Handle prompts like 'what is the cpu for my hostname'.
    Extract 'cpu' and 'hostname', match to real metric & instance.
    """
    # e.g. 'what is the cpu for host123'
    m = re.search(r"what\s+is\s+the\s+(\w+)\s+for\s+(\S+)", prompt.lower())
    if not m:
        return None
    metric_kw, host_kw = m.groups()
    names = fetch_label("__name__")
    insts = fetch_label("instance")

    # match metric
    metric_candidates = [n for n in names if metric_kw in n.lower()]
    # match instance
    host_candidates = [h for h in insts if host_kw in h.lower()]

    if metric_candidates and host_candidates:
        return f'{metric_candidates[0]}{{instance="{host_candidates[0]}"}}'
    return None

@app.route("/analyze-metrics", methods=["POST"])
def analyze_metrics():
    data   = request.get_json() or {}
    prompt = (data.get("prompt") or "").strip()
    if not prompt:
        return jsonify({"ai_response": "❌ Please provide a prompt."}), 400

    # 1) Available metrics
    if is_available_metrics_query(prompt):
        return jsonify({"ai_response": handle_available_metrics(prompt)})

    # 2) Keyword+host fallback
    fh = fallback_keyword_host(prompt)
    if fh:
        promql = fh
    else:
        # 3) LLM → PromQL
        promql = generate_promql(prompt)

    if promql:
        try:
            resp = requests.get(MIMIR_QUERY, params={"query": promql}, timeout=10)
            resp.raise_for_status()
            return jsonify({"ai_response": resp.json()})
        except Exception as e:
            return jsonify({"ai_response": f"❌ Error querying Mimir: {e}"}), 500

    # 4) Final fallback: suggest metrics
    names = fetch_label("__name__")
    sug   = suggest_metrics(prompt, names)
    return jsonify({
        "ai_response": (
            "❌ I couldn't create a PromQL query. "
            "Here are some metrics you might mean:\n" + sug
        )
    }), 400

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5050)
