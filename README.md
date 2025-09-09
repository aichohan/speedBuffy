# SpeedBuffy 🐕⚡

```
                         _   ___        __  __       
 ___ _ __   ___  ___  __| | / __\_   _ / _|/ _|_   _ 
/ __| '_ \ / _ \/ _ \/ _` |/__\// | | | |_| |_| | | |
\__ \ |_) |  __/  __/ (_| / \/  \ |_| |  _|  _| |_| |
|___/ .__/ \___|\___|\__,_\_____/\__,_|_| |_|  \__, |
    |_|                                        |___/ 
         __
        /  \__  /\_/\  Buffy
       /_/\___\ \_ _/  the Dog
          /  /   / \
          \_/   /_/  
```

## Why I built this
Sometimes you just want to **check your network speed quickly** without installing Python packages, Node modules, or heavy binaries like `speedtest-cli`. On a fresh Raspberry Pi or Linux box, it can be frustrating to pull in extra dependencies just for one test.

**SpeedBuffy** solves that. It’s a **zero-install speed test script** written in Bash, relying only on standard Linux utilities:

- `curl`
- `ping`
- `awk`
- `tput`

That’s it. No packages to install. Just download the script, make it executable, and run.

It’s designed to run **anywhere Linux is available** — Raspberry Pi, Debian servers, even minimal cloud VMs — and still give you:
- Latency tests
- Download tests
- Upload tests
- JSON export
- A fun ASCII UI

---

## Usage

### Quick start
```bash
chmod +x speedbuffy.sh
./speedbuffy.sh --quick
```

### Options
```
  --quick                   Run latency+download+upload (visuals) and exit
  --json                    Print JSON only and exit (no visuals/menu)
  --save-json               Like --json but also save to speedbuffy-YYYYMMDD-HHMMSS.json
  --out-json FILE           Like --json but save to FILE (and still print to stdout)
  --size MB                 Download size (default 100)
  --dlcap SEC               Download time cap (default 30)
  --ulcap SEC               Upload time cap (default 20)
  --ipv 4|6|auto            Force IP family (default auto)
  --server NAME             hetzner|thinkbroadband|tele2 (default hetzner)
  --no-color|--color        Force disable/enable colors
  --debug                   Log internals to /tmp/speedbuffy.log
```

---

## Menu Options
Run without flags:
```bash
./speedbuffy.sh
```

You’ll see an interactive menu:

```
Choose an option:
[1] Quick Test (10s latency + download + upload)
[2] Latency only (30s live)
[3] Download test
[4] Upload test
[5] Settings
[6] Export JSON (run full test + save file)
[0] Exit
```

### [1] Quick Test
- Runs a 10 second latency test with live updating bar.
- Then runs download + upload tests with per-chunk throughput in ASCII.
- Results shown on one screen with averages.

### [2] Latency only
- 30 second latency test.
- Shows packets sent/received in real time.
- Ends with average latency and jitter.

### [3] Download test
- Lets you use defaults (size, cap) or override.
- Performs per-chunk download with throughput per chunk.
- Reports total MB transferred, MB/s, Mb/s.

### [4] Upload test
- Same as download, but uploading generated zero-bytes to Tele2.
- Configurable chunk size and cap.

### [5] Settings
- Adjust server, IPv4/6, download size, caps.
- Values persist while the script is running.

### [6] Export JSON
- Runs full latency+download+upload.
- Saves results to a timestamped JSON file.
- Example filename: `speedbuffy-20250909-130000.json`

### [0] Exit
- Cleanly exits.

---

## Example Output

### Quick test (visual)
```
LATENCY — 10s live
[###########-------------------------------]  33%  3s/10s  sent:3 recv:3
...
NOW STARTING DOWNLOAD
Server: hetzner   URL: https://speed.hetzner.de/100MB.bin
Chunk:        0..5242879  Code:206  IP:88.198.248.254
This chunk:  12.532 MB/s (100.3 Mb/s)   Elapsed: 2s
Total:   17.50 MB of ~100 MB
...
RESULTS
Latency:  loss=0%  avg=13.2ms  jitter=1.5ms
Download: 11.5 MB/s (92.0 Mb/s) in 9s
Upload:   7.0 MB/s (56.0 Mb/s) in 20s
```

### JSON only
```bash
./speedbuffy.sh --json
```
Output:
```json
{"latency":{"loss_pct":0,"avg_ms":13.200,"jitter_ms":1.500},"download":{"MBps":11.532,"Mbps":92.3,"seconds":9},"upload":{"MBps":7.004,"Mbps":56.0,"seconds":20}}
```

---

## Notes
- Works great on Raspberry Pi and cloud servers.
- If HTTPS Range requests fail, SpeedBuffy auto-falls back to HTTP or full-file fetch.
- Pure ASCII (no Unicode boxes) for maximum compatibility.
- Debug mode (`--debug`) logs all curl details to `/tmp/speedbuffy.log`.

---

## License
MIT License — free to use, modify, and share.

---

## Credits
Designed by **@ai_chohan**
