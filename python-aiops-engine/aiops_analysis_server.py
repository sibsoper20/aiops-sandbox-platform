from flask import Flask, request, jsonify
import pandas as pd
import ollama

app = Flask(__name__)

def call_ollama(prompt):
    response = ollama.chat(model='llama3', messages=[{'role': 'user', 'content': prompt}])
    return response['message']['content']

@app.route('/analyze-metrics', methods=['POST'])
def analyze_metrics():
    data = request.get_json()
    question = data.get('question')
    df = pd.read_json(data.get('metrics'))
    summary = df.describe().to_string()
    prompt = f"Metrics summary:\n{summary}\n\nQuestion: {question}\nWhat should we do?"
    return jsonify({"analysis": call_ollama(prompt)})

@app.route('/analyze-logs', methods=['POST'])
def analyze_logs():
    data = request.get_json()
    logs = data.get('logs')
    question = data.get('question')
    prompt = f"Logs:\n{logs}\n\nQuestion: {question}\nWhat do you conclude?"
    return jsonify({"analysis": call_ollama(prompt)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
