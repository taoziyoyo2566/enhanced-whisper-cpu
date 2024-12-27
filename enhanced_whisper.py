import argparse
import logging
from pathlib import Path
import time
import json
import torch
from faster_whisper import WhisperModel
import whisperx
import gc

class EnhancedTranscriber:
    def __init__(
        self,
        model_size: str = "base",
        device: str = "cpu",
        compute_type: str = "float32"
    ):
        """
        初始化转录器
        :param model_size: 模型大小
        :param device: 运行设备
        :param compute_type: 计算精度
        """
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        
        # 初始化 Faster Whisper
        logging.info("加载 Faster Whisper 模型...")
        self.faster_model = WhisperModel(
            model_size,
            device=device,
            compute_type=compute_type,
            download_root="./models"
        )
        
        # WhisperX 模型会在需要时加载
        self.alignment_model = None
        
    def transcribe(
        self,
        audio_path: str,
        output_dir: str,
        align_output: bool = True,
        detect_speakers: bool = True
    ):
        """
        转录音频文件
        :param audio_path: 音频文件路径
        :param output_dir: 输出目录
        :param align_output: 是否使用 WhisperX 对齐
        :param detect_speakers: 是否检测说话人
        """
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        base_name = Path(audio_path).stem
        
        start_time = time.time()
        logging.info(f"开始处理音频: {audio_path}")
        
        # 第一步：使用 Faster Whisper 进行初始转录
        logging.info("使用 Faster Whisper 转录...")
        segments, info = self.faster_model.transcribe(
            audio_path,
            language="ja",
            beam_size=5,
            word_timestamps=True,
            initial_prompt="これから聞く音声は日本語能力試験の聴解問題です。"
        )
        
        # 将 segments 转换为列表
        segments_list = list(segments)
        
        # 如果需要进行对齐
        if align_output:
            logging.info("使用 WhisperX 进行时间戳对齐...")
            try:
                # 加载 WhisperX
                device = "cuda" if torch.cuda.is_available() else "cpu"
                alignment_model, metadata = whisperx.load_align_model(
                    language_code="ja",
                    device=device
                )
                
                # 准备 WhisperX 所需的格式
                whisperx_result = {
                    "segments": [
                        {
                            "start": s.start,
                            "end": s.end,
                            "text": s.text,
                            "words": [{"word": w.word, "start": w.start, "end": w.end} 
                                    for w in (s.words or [])]
                        }
                        for s in segments_list
                    ]
                }
                
                # 进行对齐
                result_aligned = whisperx.align(
                    whisperx_result["segments"],
                    alignment_model,
                    metadata,
                    audio_path,
                    device
                )
                
                # 如果需要检测说话人
                if detect_speakers and device != "cpu":
                    logging.info("检测说话人...")
                    diarize_model = whisperx.DiarizationPipeline(use_auth_token=None, device=device)
                    diarize_segments = diarize_model(audio_path)
                    result_aligned = whisperx.assign_word_speakers(diarize_segments, result_aligned)
                
                # 清理内存
                del alignment_model
                if 'diarize_model' in locals():
                    del diarize_model
                gc.collect()
                torch.cuda.empty_cache()
                
                # 使用对齐后的结果
                segments_list = result_aligned["segments"]
            
            except Exception as e:
                logging.warning(f"对齐过程出错: {e}. 使用原始转录结果。")
        
        # 保存结果
        self._save_outputs(segments_list, output_path, base_name)
        
        elapsed_time = time.time() - start_time
        logging.info(f"处理完成！用时: {elapsed_time:.2f} 秒")
    
    def _save_outputs(self, segments, output_path: Path, base_name: str):
        """保存各种格式的输出"""
        # 保存 SRT
        srt_path = output_path / f"{base_name}.srt"
        with open(srt_path, "w", encoding="utf-8") as srt_file:
            for i, segment in enumerate(segments, 1):
                print(f"{i}", file=srt_file)
                print(f"{self._format_timestamp(segment['start'])} --> {self._format_timestamp(segment['end'])}",
                      file=srt_file)
                text = segment['text']
                if 'speaker' in segment:
                    text = f"[{segment['speaker']}] {text}"
                print(f"{text}\n", file=srt_file)
        
        # 保存文本文件
        txt_path = output_path / f"{base_name}.txt"
        with open(txt_path, "w", encoding="utf-8") as txt_file:
            for segment in segments:
                timestamp = f"[{self._format_timestamp(segment['start'])} --> {self._format_timestamp(segment['end'])}]"
                text = segment['text']
                if 'speaker' in segment:
                    text = f"[{segment['speaker']}] {text}"
                print(f"{timestamp}\n{text}\n", file=txt_file)
        
        # 保存详细 JSON
        json_path = output_path / f"{base_name}.json"
        with open(json_path, "w", encoding="utf-8") as json_file:
            json.dump(segments, json_file, ensure_ascii=False, indent=2)
    
    @staticmethod
    def _format_timestamp(seconds: float) -> str:
        """格式化时间戳为 SRT 格式"""
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        millisecs = int((seconds * 1000) % 1000)
        return f"{hours:02d}:{minutes:02d}:{secs:02d},{millisecs:03d}"

def main():
    parser = argparse.ArgumentParser(description="Enhanced Whisper Audio Transcriber")
    parser.add_argument("audio_path", help="输入音频文件路径")
    parser.add_argument("--output", "-o", default="./output", help="输出目录")
    parser.add_argument(
        "--model",
        default="base",
        choices=["tiny", "base", "small", "medium", "large-v3"],
        help="模型大小"
    )
    parser.add_argument(
        "--device",
        default="cuda" if torch.cuda.is_available() else "cpu",
        choices=["cpu", "cuda"],
        help="运行设备"
    )
    parser.add_argument(
        "--no-align",
        action="store_true",
        help="禁用 WhisperX 对齐"
    )
    parser.add_argument(
        "--no-speakers",
        action="store_true",
        help="禁用说话人检测"
    )
    
    args = parser.parse_args()
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    transcriber = EnhancedTranscriber(
        model_size=args.model,
        device=args.device
    )
    
    transcriber.transcribe(
        args.audio_path,
        args.output,
        align_output=not args.no_align,
        detect_speakers=not args.no_speakers and args.device == "cuda"
    )

if __name__ == "__main__":
    main()
