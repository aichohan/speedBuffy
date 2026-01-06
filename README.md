# 🚀 speedBuffy

```
                         _   ___        __  __       
 ___ _ __   ___  ___  __| | / __\_   _ / _|/ _|_   _ 
/ __| '_ \ / _ \/ _ \/ _` |/__\// | | | |_| |_| | | |
\__ \ |_) |  __/  __/ (_| / \/  \ |_| |  _|  _| |_| |
|___/ .__/ \___|\___|\__,_\_____/\__,_|_| |_|  \__, |
    |_|                                        |___/ 
         __
        /  \__  /\_/\  Buffy
       /\_/  _/  \_ _/  the Dog
          /  /   / \
          \_/   /_/  
```

A zero-install ASCII speed test for Linux/Raspberry Pi systems.

## 🤔 Why speedBuffy?

You often need a quick, clean speed test without installing packages or heavy binaries. SpeedBuffy is a zero-install script that uses native Linux tools to measure latency, download, and upload speeds, with live ASCII visuals and JSON for CI/automation.

speedBuffy relies only on common tools found in most Linux distributions:
- `bash` - For script execution
- `curl` - For download/upload tests
- `ping` - For latency tests
- `awk` - For calculations
- `tput` - For terminal formatting
- `coreutils` - For basic operations (date, dd, etc.)

## 🚀 Quick Start

### Get SpeedBuffy

#### Option 1: Clone Repository (Recommended)
```bash
# Clone the repository
git clone https://github.com/aichohan/speedBuffy.git

# Navigate to the directory
cd speedBuffy

# Make the script executable
chmod +x speedbuffy.sh
```

#### Option 2: Direct Download (Quick Try)
```bash
# Download just the script file
curl -O https://raw.githubusercontent.com/aichohan/speedBuffy/main/speedbuffy.sh

# Make executable and run
chmod +x speedbuffy.sh
./speedbuffy.sh --help
```

### Run Your First Test
```bash
# Quick speed test (recommended for first run)
./speedbuffy.sh --quick

# Or start with interactive menu
./speedbuffy.sh

# Or get JSON results
./speedbuffy.sh --json --size 10
```

### Verify Everything Works
```bash
# Test all functionality with a small file
./speedbuffy.sh --debug --json --size 5

# Check debug log if needed
cat /tmp/speedbuffy.log
```

## 📋 Usage

### Quick Examples

```bash
# Run with interactive menu
./speedBuffy.sh

# Run quick test with visuals and exit
./speedBuffy.sh --quick

# Output JSON to stdout
./speedBuffy.sh --json

# Save JSON to timestamped file
./speedBuffy.sh --save-json

# Save JSON to specific file
./speedBuffy.sh --out-json results.json

# Run quick test with custom download size
./speedBuffy.sh --size 50 --quick
```

### ⚙️ Command Line Options

```
Options:
  --quick               Run full visual test and exit
  --json                Output JSON to stdout only, no visuals
  --save-json           Like --json + save to timestamped file
  --out-json FILE       Like --json + save to specified FILE
  --size MB             Set download size in MB (default: 100)
  --dlcap SEC           Set download time cap in seconds (default: 30)
  --ulcap SEC           Set upload time cap in seconds (default: 30)
  --ipv 4|6|auto        Set IP version preference (default: auto)
  --no-color            Disable colored output
  --color               Force colored output
  --debug               Write verbose logs to /tmp/speedbuffy.log
  -h, --help            Show this help message
```

### Menu Mode

When run without arguments, SpeedBuffy presents an interactive menu:

1. **Quick Test** - Runs latency, download, and upload tests in sequence
2. **Latency Test Only** - Measures packet loss, average latency, and jitter
3. **Download Test Only** - Measures download speed
4. **Upload Test Only** - Measures upload speed
5. **Settings** - Configure test parameters and server selection
6. **Export JSON** - Run tests and save results to a timestamped JSON file
7. **Exit** - Quit SpeedBuffy

The main menu also displays your current server selections for latency, download, and upload tests.

#### Server Selection

Each test (Quick, Latency, Download, Upload) offers the option to:
- Use the default server(s)
- Select a specific server for that test

For example, when running a latency test:
```
LATENCY TEST

1. Use default server (8.8.8.8)
2. Select a different server

Select an option (1-2): 2

Select latency server:
1. Google DNS (8.8.8.8)
2. Cloudflare DNS (1.1.1.1)
3. OpenDNS (208.67.222.222)
4. Custom server
```

#### Settings Menu

The Settings menu provides access to:
- Download Size configuration
- Download Time Cap configuration
- Upload Time Cap configuration
- IP Version selection
- Server Settings submenu

The Server Settings submenu allows you to configure default servers for all tests:
```
SERVER SETTINGS

1. Latency Server: 8.8.8.8
2. Download Server: All Available Servers
3. Upload Server: All Available Servers
4. Return to Settings
```

### Sample Visual Output

```
SERVER SELECTION

1. Use default servers
2. Select servers for this test

Select an option (1-2): 2

Select latency server:
1. Google DNS (8.8.8.8)
2. Cloudflare DNS (1.1.1.1)
3. OpenDNS (208.67.222.222)
4. Custom server
Select an option (1-4): 1

Select download server:
1. Cloudflare (https://speed.cloudflare.com/__down)
2. HTTPBin (https://httpbin.org/stream-bytes)
3. OTEnet (http://speedtest.ftp.otenet.gr/files/)
4. Tele2 (http://speedtest.tele2.net/)
5. Custom server
6. Use all servers (default)
Select an option (1-6): 1

Select upload server:
1. HTTPBin (https://httpbin.org/post)
2. Postman Echo (https://postman-echo.com/post)
3. Custom server
4. Use all servers (default)
Select an option (1-4): 1

Starting latency test to 8.8.8.8...

[##########] 100%

Latency test completed.
Packet Loss: 0%
Average Latency: 24.35 ms
Jitter: 3.21 ms

Starting download test (100MB, 30s cap)...

Trying server: https://speed.cloudflare.com/__down?bytes=100000000
Downloading chunk 10/10: [##########] 100%

Download test completed.
Speed: 12.45 MB/s (99.60 Mb/s)
Time: 8.03 seconds
```

### Test Results Display

```
TEST RESULTS

Latency:
  Server: 8.8.8.8
  Packet Loss: 0%
  Average: 24.35 ms
  Jitter: 3.21 ms

Download:
  Server: https://speed.cloudflare.com/__down?bytes=100000000
  Speed: 12.45 MB/s (99.60 Mb/s)
  Time: 8.03 seconds

Upload:
  Server: https://httpbin.org/post
  Speed: 5.32 MB/s (42.56 Mb/s)
  Time: 1.88 seconds
```

### Sample JSON Output

```json
{"latency":{"server":"8.8.8.8","loss_pct":0,"avg_ms":24.35,"jitter_ms":3.21},"download":{"server":"https://speed.cloudflare.com/__down?bytes=100000000","MBps":12.45,"Mbps":99.60,"seconds":8.03},"upload":{"server":"https://httpbin.org/post","MBps":5.32,"Mbps":42.56,"seconds":1.88}}
```

## Robustness Features

- **Multiple Fallbacks**: If a test server fails, SpeedBuffy automatically tries alternative servers
- **Comprehensive Server Selection**: Choose from predefined servers or specify custom ones for all test types
- **Per-Test Server Selection**: Select servers individually for each test you run
- **Current Server Display**: Main menu shows which servers are currently selected
- **Server Reporting**: All outputs (visual, JSON, file) include the servers used for each test
- **Error Handling**: Gracefully handles network issues and timeouts
- **ASCII-only UI**: Works in any terminal without Unicode support
- **Color Auto-detection**: Automatically disables color when stdout isn't a TTY
- **Numeric Sanitization**: All values are sanitized to avoid blank/null values
- **Debug Logging**: Use `--debug` to write detailed logs to `/tmp/speedbuffy.log`
- **Zero Dependencies**: Uses only tools commonly available on Linux systems

## Default Server Configuration

By default, SpeedBuffy uses:
- Cloudflare for download tests
- Postman Echo (primary) and HTTPBin (fallback) for upload tests

## System Requirements

### Supported Platforms
- ✅ Linux (all distributions)
- ✅ Raspberry Pi OS
- ✅ macOS (with bash installed)
- ✅ Windows WSL/WSL2

### Required Tools
All commands must be available in PATH:
```bash
# Check if you have required tools
which bash curl ping awk tput date dd

# Most systems have these by default, if not:
# Ubuntu/Debian: apt install curl iputils-ping gawk ncurses-bin coreutils
# RHEL/CentOS: yum install curl iputils gawk ncurses coreutils
# macOS: brew install curl gawk ncurses coreutils
```

## Troubleshooting

### Upload Tests Show 0.00 MB/s
This was a known issue that has been **fixed** as of January 2026. If you still see this:
```bash
# Update to latest version
git pull origin main

# Test with debug logging
./speedbuffy.sh --debug --json --size 5
cat /tmp/speedbuffy.log
```

### Network/Connectivity Issues
```bash
# Test server connectivity manually
curl -I https://postman-echo.com/post
curl -I https://httpbin.org/post
curl -I https://speed.cloudflare.com/__down

# Test with different file sizes
./speedbuffy.sh --json --size 1   # Small test
./speedbuffy.sh --json --size 50  # Medium test
```

### Permission Denied Errors
```bash
# Make sure script is executable
chmod +x speedbuffy.sh

# Check file permissions
ls -la speedbuffy.sh

# Should show: -rwxr-xr-x (executable for owner)
```

### Script Won't Run
```bash
# Check bash syntax
bash -n speedbuffy.sh

# Run with explicit bash
bash ./speedbuffy.sh --help

# Check bash version (requires bash 4.0+)
bash --version
```

## Recent Updates

### January 2026 - Critical Fixes ✅
- **Fixed upload test failures** for file sizes 1-9 MB (integer division bug)
- **Added HTTPBin fallback server** for improved reliability
- **Enhanced error handling** with minimum file size constraints
- **All file sizes now work correctly** - no more 0.00 MB/s upload speeds

### Features
- Zero-install design with ASCII progress bars
- Multiple output formats (visual, JSON, timestamped files)
- Configurable server selection and test parameters
- Comprehensive debug logging for troubleshooting

## License

MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

Designed by [@ai_chohan](https://github.com/ai_chohan)
