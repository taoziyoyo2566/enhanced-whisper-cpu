# Dockerfile
FROM python:3.11-slim

# 设置非交互模式和时区
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV PYTHONUNBUFFERED=1
ENV WHISPER_MODEL_DIR=/app/models

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    tzdata \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 复制应用文件
COPY enhanced_whisper.py .
COPY requirements.txt .

# 创建必要的目录
RUN mkdir -p /app/input /app/output /app/models

# 安装 Python 依赖（CPU 版本）
RUN pip3 install --no-cache-dir torch torchaudio --index-url https://download.pytorch.org/whl/cpu && \
    pip3 install --no-cache-dir -r requirements.txt && \
    pip3 install --no-cache-dir git+https://github.com/m-bain/whisperX.git

# 设置卷
VOLUME ["/app/input", "/app/output", "/app/models"]

# 入口命令
ENTRYPOINT ["python3", "enhanced_whisper.py"]
CMD ["--help"]
