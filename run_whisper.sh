#!/bin/bash

# 创建必要的目录
mkdir -p {input,output,models,logs}

# 解析命令行参数
while getopts "f:m:" opt; do
    case $opt in
        f) AUDIO_FILE="$OPTARG";;
        m) MODEL_SIZE="$OPTARG";;
        \?) echo "Invalid option -$OPTARG" >&2
            exit 1;;
        :) echo "Option -$OPTARG requires an argument." >&2
            exit 1;;
    esac
done

# 检查必要参数
if [ -z "$AUDIO_FILE" ] || [ -z "$MODEL_SIZE" ]; then
    echo "Usage: $0 -f <audio_file> -m <model_size>"
    echo "Example: $0 -f myaudio.mp3 -m large-v3"
    exit 1
fi

# 检查文件是否存在
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file $AUDIO_FILE not found!"
    exit 1
fi

# 复制音频文件到输入目录
cp "$AUDIO_FILE" input/

# 获取文件名
FILENAME=$(basename "$AUDIO_FILE")

# 检查是否有相同model_size的容器（包括已停止的）
EXISTING_CONTAINER=$(docker ps -a --format '{{.Names}}' | grep "whisper_${MODEL_SIZE}_" | head -n 1)

if [ -n "$EXISTING_CONTAINER" ]; then
    echo "Found existing container: $EXISTING_CONTAINER"
    CONTAINER_NAME="$EXISTING_CONTAINER"
    
    # 检查容器状态
    CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER_NAME")
    
    # 如果容器不在运行状态，则重启它
    if [ "$CONTAINER_STATUS" != "running" ]; then
        echo "Restarting existing container..."
        docker start "$CONTAINER_NAME"
    fi
else
    # 创建新的容器名（基于时间戳避免冲突）
    CONTAINER_NAME="whisper_${MODEL_SIZE}_$(date +%Y%m%d_%H%M%S)"
    echo "Creating new container: $CONTAINER_NAME"
fi

echo "Starting transcription in background..."
echo "Container name: $CONTAINER_NAME"
echo "Audio file: $FILENAME"
echo "Model: $MODEL_SIZE"

if [ -n "$EXISTING_CONTAINER" ]; then
    # 使用现有容器处理文件
    docker exec -d "$CONTAINER_NAME" python3 enhanced_whisper.py "input/$FILENAME" --model "$MODEL_SIZE"
else
    # 运行新容器在后台
    docker compose run -d \
        --name "$CONTAINER_NAME" \
        whisper "input/$FILENAME" --model "$MODEL_SIZE"
fi

echo "
Transcription started in background. To monitor:

    View logs:    docker logs -f $CONTAINER_NAME
    Check status: docker ps | grep $CONTAINER_NAME
    Stop task:    docker stop $CONTAINER_NAME
    
Output will be in the 'output' directory when complete.
"
