#!/bin/bash

echo "🚀 Starting AIOps Sandbox Environment"

# Step 1: Start Docker stack
echo "🔄 Starting Docker containers (Loki, Mimir, PostgreSQL, Ollama)..."
cd docker || exit
docker-compose up -d
cd ..

# Step 2: Start Ollama server (daemon)
echo "🤖 Starting Ollama daemon in background..."
nohup ollama serve > ollama.log 2>&1 &

# Step 3: Start Python AIOps engine
echo "🐍 Starting Python AI engine..."
cd python-aiops-engine || exit
pip install -r requirements.txt
python aiops_analysis_server.py
