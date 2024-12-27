#!/bin/bash

# 创建必要的目录
mkdir -p {input,output,models,logs}

# 检查参数
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <audio_file> <model_size>"
    echo "Example: $0 myaudio.mp3 large-v3"
    exit 1
fi

AUDIO_FILE="$1"
MODEL_SIZE="$2"

# 检查文件是否存在
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file $AUDIO_FILE not found!"
    exit 1
fi

# 复制音频文件到输入目录
cp "$AUDIO_FILE" input/

# 获取文件名
FILENAME=$(basename "$AUDIO_FILE")

# 创建容器名（基于时间戳避免冲突）
CONTAINER_NAME="whisper_${MODEL_SIZE}_$(date +%Y%m%d_%H%M%S)"

echo "Starting transcription in background..."
echo "Container name: $CONTAINER_NAME"
echo "Audio file: $FILENAME"
echo "Model: $MODEL_SIZE"

# 运行容器在后台
docker-compose run -d \
    --name "$CONTAINER_NAME" \
    whisper "input/$FILENAME" --model "$MODEL_SIZE"

echo "
Transcription started in background. To monitor:

    View logs:    docker logs -f $CONTAINER_NAME
    Check status: docker ps | grep $CONTAINER_NAME
    Stop task:    docker stop $CONTAINER_NAME
    
Output will be in the 'output' directory when complete.
"
