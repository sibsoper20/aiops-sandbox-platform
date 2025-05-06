# AIOps Sandbox Platform

## Structure
- `backend-java/`: Spring Boot app (UI + API orchestration)
- `python-aiops-engine/`: Python service (analytics + LLM via Ollama)
- `docker/`: Loki, Mimir, PostgreSQL, Ollama services
- `architecture-diagram/`: System diagram

## Run Guide

### Step 1: Start Docker Services
```bash
cd docker/
docker-compose up -d
```

### Step 2: Run Python Microservice
```bash
cd python-aiops-engine/
pip install -r requirements.txt
python aiops_analysis_server.py
```

### Step 3: Run Spring Boot App
```bash
cd backend-java/
./mvnw spring-boot:run
```

Then go to http://localhost:8080
