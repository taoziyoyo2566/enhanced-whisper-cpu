
# run.sh
#!/bin/bash
set -e

# 检查输入参数
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <audio_file> [additional_whisper_args...]"
    exit 1
fi

# 获取音频文件路径
AUDIO_FILE="$1"
shift  # 移除第一个参数，保留剩余参数

# 检查文件是否存在
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file '$AUDIO_FILE' not found!"
    exit 1
fi

# 创建必要的目录
mkdir -p input output models

# 复制音频文件到输入目录
cp "$AUDIO_FILE" input/

# 获取文件名
FILENAME=$(basename "$AUDIO_FILE")

# 强制使用 CPU 模式运行
echo "Processing $FILENAME with CPU mode..."
docker-compose run --rm whisper "input/$FILENAME" --device cpu "$@"

# 清理输入文件
rm "input/$FILENAME"

echo "Done! Check the output directory for results."
