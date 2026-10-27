#!/usr/bin/env python3
"""Pinned build inputs only. No runtime networking; never processes user records.
Run python3 Scripts/on-device-ai/prepare.py. Downloads go to ignored local cache.
"""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, sys, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = ROOT / '.local-ai-cache'
MANIFEST = json.loads((ROOT/'Models/manifest.json').read_text())
def run(args, cwd=ROOT, env=None):
    print(' '.join(map(str,args)), flush=True)
    subprocess.run(list(map(str,args)), cwd=cwd, env=env, check=True)
def digest(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for chunk in iter(lambda:f.read(8*1024*1024),b''): h.update(chunk)
    return h.hexdigest()
def download(url, path, checksum):
    if not path.exists() or digest(path)!=checksum:
        temporary=path.with_suffix(path.suffix+'.partial')
        urllib.request.urlretrieve(url,temporary)
        if digest(temporary)!=checksum: raise RuntimeError('Checksum mismatch: '+str(path))
        temporary.replace(path)
    return path

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--engine-only", action="store_true", help="Build iOS/macOS engine without downloading model weights")
    args=parser.parse_args()
    CACHE.mkdir(exist_ok=True)
    e=MANIFEST['engine']; tag=e['tag']; base='https://github.com/ggml-org/llama.cpp'
    download(f'{base}/archive/refs/tags/{tag}.tar.gz',CACHE/'source.tar.gz',e['sourceSHA256'])
    download(f'{base}/releases/download/{tag}/llama-{tag}-xcframework.zip',CACHE/'llama.zip',e['xcframeworkSHA256'])
    download(f'{base}/releases/download/{tag}/llama-{tag}-bin-macos-arm64.tar.gz',CACHE/'macos.tar.gz',e['macosSHA256'])
    source=CACHE/f'llama.cpp-{tag}'
    if not source.exists(): run(['tar','-xzf',CACHE/'source.tar.gz','-C',CACHE])
    if not (CACHE/'build-apple').exists(): run(['unzip','-q',CACHE/'llama.zip','-d',CACHE])
    if not (CACHE/f'llama-{tag}').exists(): run(['tar','-xzf',CACHE/'macos.tar.gz','-C',CACHE])
    venv=CACHE/'venv'
    if not venv.exists(): run([sys.executable,'-m','venv',venv])
    python=venv/'bin/python'; pip=venv/'bin/pip'
    run([pip,'install','cmake==4.4.4'])
    simulator=source/'build-apple/llama.xcframework'
    if not simulator.exists():
        env=dict(os.environ,PATH=str(venv/'bin')+os.pathsep+os.environ['PATH'])
        run(['bash','build-xcframework.sh','ios-sim'],cwd=source,env=env)
    artifact=ROOT/'Packages/TrainoteLlama/Artifacts/llama.xcframework'
    if not artifact.exists():
        artifact.parent.mkdir(exist_ok=True)
        release=CACHE/'build-apple/llama.xcframework'
        run(['xcodebuild','-create-xcframework','-framework',release/'ios-arm64/llama.framework','-framework',simulator/'ios-arm64_x86_64-simulator/llama.framework','-framework',release/'macos-arm64_x86_64/llama.framework','-output',artifact])
    if args.engine_only:
        print('Prepared pinned engine only')
        return
    run([pip,'install','-r',ROOT/'Scripts/on-device-ai/requirements.txt'])
    m=MANIFEST['model']; hf=CACHE/'hf'
    run([python,'-c',"from huggingface_hub import snapshot_download; snapshot_download("+repr(m['repository'])+",revision="+repr(m['revision'])+",local_dir="+repr(str(hf))+",allow_patterns=['*.json','*.safetensors','tokenizer.model','LICENSE','README.md'])"])
    if digest(hf/'model.safetensors')!=m['sourceSHA256']: raise RuntimeError('Source model checksum mismatch')
    bf16=CACHE/'qwen3-0.6b-bf16.gguf'; output=ROOT/'Models'/m['filename']
    if not bf16.exists(): run([python,source/'convert_hf_to_gguf.py',hf,'--outfile',bf16,'--outtype','bf16'])
    if not output.exists(): run([CACHE/f'llama-{tag}/llama-quantize',bf16,output,'Q4_K_M'])
    if digest(output)!=m['sha256']: raise RuntimeError('Q4 model checksum mismatch')
    r=MANIFEST['reference']
    download(f"https://huggingface.co/{r['repository']}/resolve/{r['revision']}/{r['filename']}",CACHE/'qwen3-0.6b-q8_0.gguf',r['sha256'])
    print('Prepared and verified',output)
if __name__=='__main__': main()
