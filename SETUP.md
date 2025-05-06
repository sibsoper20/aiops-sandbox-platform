# ✅ AIOps Sandbox - Prerequisites Installation Guide

This file helps you install all required tools before running the AIOps Sandbox.

---

## 1. Docker + Docker Compose

**Why:** Used to run Loki, Mimir, PostgreSQL, Ollama.

### Install:

- **macOS:** [https://docs.docker.com/desktop/mac/install/](https://docs.docker.com/desktop/mac/install/)
- **Windows:** [https://docs.docker.com/desktop/windows/install/](https://docs.docker.com/desktop/windows/install/)
- **Linux:**
```bash
sudo apt update
sudo apt install docker.io docker-compose -y
sudo systemctl enable docker
```

### Verify:
```bash
docker --version
docker-compose --version
```

---

## 2. Ollama (Local LLM)

**Why:** Runs local AI (e.g. LLaMA3) to answer AIOps questions.

### Install:
- Go to: https://ollama.com/download
- Or use:
```bash
brew install ollama  # macOS
```

### Run Ollama:
```bash
ollama run llama3
```

---

## 3. Python 3.10+ and pip

**Why:** Required for the Python AI engine.

### Install:

- **macOS:** `brew install python`
- **Windows:** [https://www.python.org/downloads/windows/](https://www.python.org/downloads/windows/)
- **Linux:**
```bash
sudo apt update
sudo apt install python3 python3-pip -y
```

### Verify:
```bash
python3 --version
pip --version
```

---

## 4. Java 17+

**Why:** Required for Spring Boot backend.

### Install:

- **macOS:** `brew install openjdk@17`
- **Windows:** Use Adoptium Temurin: https://adoptium.net/
- **Linux:**
```bash
sudo apt install openjdk-17-jdk -y
```

### Verify:
```bash
java -version
```

---

## 5. Maven

**Why:** Builds and runs the Spring Boot project.

### Install:

- **macOS:** `brew install maven`
- **Windows:** [https://maven.apache.org/download.cgi](https://maven.apache.org/download.cgi)
- **Linux:**
```bash
sudo apt install maven -y
```

### Verify:
```bash
mvn -version
```

---

## ✅ Summary Checklist

| Tool           | Check Command         |
|----------------|------------------------|
| Docker         | `docker --version`     |
| Docker Compose | `docker-compose --version` |
| Ollama         | `ollama run llama3`    |
| Python         | `python3 --version`    |
| pip            | `pip --version`        |
| Java           | `java -version`        |
| Maven          | `mvn -version`         |



---

## ▶️ Optional: Run Everything with One Command

After all tools are installed, you can use the provided helper script:

```bash
./dev-start.sh
```

This will:
1. Start Docker (Loki, Mimir, PostgreSQL, Ollama)
2. Launch the Ollama daemon (`ollama serve`)
3. Start the Python AIOps engine

> 🔄 You can then manually open a new terminal and run Spring Boot:
```bash
cd backend-java
./mvnw spring-boot:run
```
