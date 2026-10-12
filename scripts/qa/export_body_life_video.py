"""Encode rendered WebP frames as an ordinary H.264 review video (no AI video generation)."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
from PIL import Image


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input',type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args();out=args.output or args.input.with_suffix('.mp4')
    ffmpeg=shutil.which('ffmpeg');assert ffmpeg,'ffmpeg is unavailable'
    image=Image.open(args.input);duration=0
    for i in range(image.n_frames):image.seek(i);image.load();duration+=image.info.get('duration',0)
    assert duration>0,'Missing frame durations'
    width,height=image.size;fps=image.n_frames*1000/duration
    out.parent.mkdir(parents=True,exist_ok=True)
    command=[ffmpeg,'-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{width}x{height}','-r',str(fps),'-i','pipe:0','-an','-c:v','libx264','-crf','16','-pix_fmt','yuv420p','-movflags','+faststart',str(out)]
    process=subprocess.Popen(command,stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        for i in range(image.n_frames):image.seek(i);process.stdin.write(image.convert('RGB').tobytes())
    finally:process.stdin.close()
    error=process.stderr.read().decode();assert process.wait()==0,error
    probe=subprocess.run([shutil.which('ffprobe'),'-v','error','-select_streams','v:0','-show_entries','stream=codec_name,width,height,nb_frames,r_frame_rate,duration','-of','json',str(out)],capture_output=True,text=True,check=True)
    metadata=json.loads(probe.stdout)['streams'][0]
    assert int(metadata['nb_frames'])==image.n_frames and abs(float(metadata['duration'])-duration/1000)<.02,metadata
    print(json.dumps({'file':str(out),'bytes':out.stat().st_size,**metadata},indent=2))

if __name__=='__main__':main()
