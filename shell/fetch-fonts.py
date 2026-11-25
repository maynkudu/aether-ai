#!/usr/bin/env python3
"""Install selected OFL fonts from Google Fonts into the user's font directory."""
import os
import pathlib
import shutil
import subprocess
import urllib.parse
import urllib.request
import tempfile

BASE = "https://raw.githubusercontent.com/google/fonts/main/ofl/"
FONTS = {
    "inter": ["Inter[opsz,wght].ttf"],
    "manrope": ["Manrope[wght].ttf"],
    "montserrat": ["Montserrat[wght].ttf"],
    "poppins": ["Poppins-Regular.ttf", "Poppins-Medium.ttf", "Poppins-SemiBold.ttf", "Poppins-Bold.ttf"],
    "dmsans": ["DMSans[opsz,wght].ttf"],
    "plusjakartasans": ["PlusJakartaSans[wght].ttf"],
    "spacegrotesk": ["SpaceGrotesk[wght].ttf"],
    "outfit": ["Outfit[wght].ttf"],
    "sora": ["Sora[wght].ttf"],
    "figtree": ["Figtree[wght].ttf"],
    "rubik": ["Rubik[wght].ttf"],
    "notosans": ["NotoSans[wdth,wght].ttf"],
    "jetbrainsmono": ["JetBrainsMono[wght].ttf"],
}
def get(family, filename):
    url = BASE + family + "/" + urllib.parse.quote(filename)
    req = urllib.request.Request(url, headers={"User-Agent":"aether.ai/font-pack"})
    with urllib.request.urlopen(req, timeout=25) as response:
        if not response.geturl().startswith("https://"):
            raise ValueError("non-HTTPS redirect")
        data = response.read(8*1024*1024+1)
    if not data or len(data)>8*1024*1024:
        raise ValueError("invalid download size")
    if filename.endswith(".ttf") and data[:4] not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
        raise ValueError("invalid font header")
    if filename=="OFL.txt" and b"SIL OPEN FONT LICENSE" not in data.upper():
        raise ValueError("OFL license not found")
    return data

def main():
    dest = pathlib.Path(os.environ.get("XDG_DATA_HOME") or pathlib.Path.home()/".local/share")/"fonts"/"aether-ai"
    dest.mkdir(parents=True,exist_ok=True)
    failures=[]
    for family, files in FONTS.items():
        folder=dest/family
        try:
            # Download/validate complete family and license before changing files.
            with tempfile.TemporaryDirectory(dir=dest) as tmp:
                temp=pathlib.Path(tmp)
                for filename in ["OFL.txt",*files]:
                    (temp/filename).write_bytes(get(family,filename))
                folder.mkdir(exist_ok=True)
                for file in temp.iterdir():
                    os.replace(file,folder/file.name)
            print("Installed font:",family)
        except Exception as exc:
            failures.append(family)
            print("Font unavailable:",family,"-",exc)
    if shutil.which("fc-cache"):
        subprocess.run(["fc-cache","-f",str(dest)],check=False,timeout=60)
    print("Font directory:",dest)
    if failures:
        print("Retry --fetch-fonts for:",", ".join(failures))
    print("Restart aether to refresh the installed font list.")
if __name__=="__main__":
    main()
