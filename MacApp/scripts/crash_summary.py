"""Print the crashing thread from the newest MorseEye crash report (.ips), for CI."""
import glob
import json
import os

reports = sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/MorseEye*.ips")),
                 key=os.path.getmtime)
if not reports:
    print("(no crash report found)")
    raise SystemExit
text = open(reports[-1]).read()
header, _, body = text.partition("\n")
crash = json.loads(body)
exc = crash.get("exception", {})
print("exception:", exc.get("type"), exc.get("signal"), crash.get("asi", ""))
images = crash.get("usedImages", [])
for thread in crash.get("threads", []):
    if not thread.get("triggered"):
        continue
    for frame in thread.get("frames", [])[:25]:
        image = images[frame["imageIndex"]].get("name", "?") if frame.get("imageIndex", -1) < len(images) else "?"
        loc = f' {frame.get("sourceFile")}:{frame.get("sourceLine")}' if frame.get("sourceFile") else ""
        print(f'  {image}  {frame.get("symbol", hex(frame.get("imageOffset", 0)))}{loc}')
