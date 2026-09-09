#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
import urllib.request
import zipfile

def load_tokens():
    gh_token = os.environ.get("GH_TOKEN", "")
    gitea_token = os.environ.get("GITEA_TOKEN", "")
    cred_file = os.path.expanduser("~/.git-credentials")
    if os.path.isfile(cred_file):
        with open(cred_file) as f:
            for line in f:
                line = line.strip()
                if "github.com" in line and not gh_token:
                    parts = line.split("@")[0].split(":")
                    if len(parts) >= 3:
                        gh_token = parts[2]
                elif "10.100.0.1" in line and not gitea_token:
                    parts = line.split("@")[0].split(":")
                    if len(parts) >= 3:
                        gitea_token = parts[2]
    return gh_token, gitea_token

GH_TOKEN, GITEA_TOKEN = load_tokens()
GITEA_API = "http://10.100.0.1:3000/api/v1/repos/ChanceFlow/easytier"
RELEASE_ID = 4196
TARGET_DIR = os.path.abspath("release-artifacts")
LOG_FILE = os.path.join(TARGET_DIR, "download.log")

def resolve_release_id(tag_name):
    try:
        req = urllib.request.Request(f"{GITEA_API}/releases/tags/{tag_name}", headers={
            "Authorization": f"token {GITEA_TOKEN}",
            "User-Agent": "curl/8.5.0"
        })
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return data.get("id")
    except Exception:
        return None

if len(sys.argv) > 1 and sys.argv[1].startswith("v"):
    resolved = resolve_release_id(sys.argv[1])
    if resolved:
        RELEASE_ID = resolved

RUN_IDS = [
    34310832436,  # GUI
    34310832401,  # Mobile
    34310832456,  # Core
]

def log(msg):
    ts = time.strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{ts} {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def get_gh_json(url):
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {GH_TOKEN}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "curl/8.5.0"
    })
    # bypass any proxy for github api or use env
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())

def get_artifact_download_url(artifact_id):
    url = f"https://api.github.com/repos/ChanceFlow/EasyTier/actions/artifacts/{artifact_id}/zip"
    cmd = [
        "curl", "-s", "-x", "http://10.100.0.6:7890",
        "-H", f"Authorization: Bearer {GH_TOKEN}",
        "-w", "%{redirect_url}", url
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    return res.stdout.strip()

def download_file(url, out_path):
    # Use reliable proxy 10.100.0.6:7890 for azure blob download
    cmd = ["curl", "-s", "-L", "-x", "http://10.100.0.6:7890", "--retry", "5", "--retry-delay", "2", "-o", out_path, url]
    res = subprocess.run(cmd)
    return res.returncode == 0

def upload_to_gitea(file_path, asset_name):
    url = f"{GITEA_API}/releases/{RELEASE_ID}/assets?name={asset_name}"
    cmd = [
        "curl", "-s", "-X", "POST",
        "--noproxy", "*",
        "-H", f"Authorization: token {GITEA_TOKEN}",
        "-F", f"attachment=@{file_path}",
        url
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    return res.returncode == 0

def main():
    os.makedirs(TARGET_DIR, exist_ok=True)
    log("=== Starting release artifact monitor and download pipeline ===")
    downloaded_artifacts = set()
    
    # Check what is already uploaded on Gitea
    existing_gitea_assets = set()
    try:
        req = urllib.request.Request(f"{GITEA_API}/releases/{RELEASE_ID}", headers={
            "Authorization": f"token {GITEA_TOKEN}",
            "User-Agent": "curl/8.5.0"
        })
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            for asset in data.get("assets", []):
                existing_gitea_assets.add(asset["name"])
        log(f"Existing Gitea assets: {len(existing_gitea_assets)}")
    except Exception as e:
        log(f"Error checking Gitea release: {e}")

    while True:
        all_finished = True
        for run_id in RUN_IDS:
            try:
                run_data = get_gh_json(f"https://api.github.com/repos/ChanceFlow/EasyTier/actions/runs/{run_id}")
                run_name = run_data.get("name", str(run_id))
                run_status = run_data.get("status")
                run_conclusion = run_data.get("conclusion")
                
                if run_status != "completed":
                    all_finished = False

                # Check artifacts
                art_data = get_gh_json(f"https://api.github.com/repos/ChanceFlow/EasyTier/actions/runs/{run_id}/artifacts")
                artifacts = art_data.get("artifacts", [])
                
                log(f"Run {run_name} ({run_id}): status={run_status}, conclusion={run_conclusion}, artifacts={len(artifacts)}")

                for art in artifacts:
                    art_id = art["id"]
                    art_name = art["name"]
                    if art_id in downloaded_artifacts:
                        continue
                    
                    zip_path = os.path.join(TARGET_DIR, f"{art_name}.zip")
                    log(f"--> Fetching artifact '{art_name}' ({art_id})...")
                    dl_url = get_artifact_download_url(art_id)
                    if not dl_url:
                        log(f"    Failed to get download URL for {art_name}")
                        continue
                    
                    if download_file(dl_url, zip_path):
                        log(f"    Downloaded {art_name}.zip ({os.path.getsize(zip_path)} bytes)")
                        downloaded_artifacts.add(art_id)
                        
                        # Unpack files inside the zip
                        extracted_files = []
                        try:
                            with zipfile.ZipFile(zip_path, 'r') as zf:
                                for member in zf.namelist():
                                    zf.extract(member, TARGET_DIR)
                                    extracted_path = os.path.join(TARGET_DIR, member)
                                    if os.path.isfile(extracted_path):
                                        extracted_files.append(extracted_path)
                            log(f"    Extracted {len(extracted_files)} files from {art_name}.zip")
                        except Exception as e:
                            log(f"    Extraction note: {e}")
                            extracted_files = [zip_path]
                        
                        # Upload extracted primary assets or the zip itself to Gitea
                        for fpath in extracted_files:
                            fname = os.path.basename(fpath)
                            if fname.endswith((".apk", ".dmg", ".deb", ".rpm", ".AppImage", ".exe", ".zip", ".tar.gz", ".tar.xz")):
                                if fname not in existing_gitea_assets:
                                    log(f"    Uploading {fname} to Gitea release...")
                                    if upload_to_gitea(fpath, fname):
                                        existing_gitea_assets.add(fname)
                                        log(f"    Uploaded {fname} to Gitea successfully!")
                    else:
                        log(f"    Failed to download {art_name}.zip")

            except Exception as e:
                log(f"Error querying run {run_id}: {e}")
                all_finished = False

        if all_finished:
            log("=== All monitored runs have completed! Finished downloading all artifacts! ===")
            break

        time.sleep(20)

if __name__ == "__main__":
    main()
