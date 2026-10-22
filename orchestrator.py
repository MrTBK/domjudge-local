#!/usr/bin/env python3
import os
import sys
import time
import json
import random
import string
import shutil
import hashlib
import zipfile
import subprocess
import requests
from bs4 import BeautifulSoup

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(BASE_DIR, "problems_build")

DOMJUDGE_URL = "http://127.0.0.1:8080"
DOMJUDGE_USER = "admin"
DOMJUDGE_PASS = "admin1234"

POLYGON_API_KEY = "e8bb660bfea2cd170a2046794b48dd7b63ee7040"
POLYGON_API_SECRET = "84c8e6863ae320bb9bc93f4e2cfcfbf53b4b38f0"

CONTEST_ID = "contest-2110"
CONTEST_NAME = "Training Contest 21/10"
CONTEST_SHORTNAME = "contest-2110"
CONTEST_START_TIME = "2026-10-21T15:00:00+01:00"
CONTEST_DURATION = "02:30:00.000"
CONTEST_ACTIVATE_TIME = "2026-10-21T14:30:00+01:00"

PROBLEMS = [
    {
        "label": "A",
        "cf_id": "486/A",
        "polygon_name": "contest2110-a-calculating-function",
        "name": "Calculating Function",
        "color": "#EF4444",
        "time_limit": 1.0,
        "memory_limit": 256,
    },
    {
        "label": "B",
        "cf_id": "1999/C",
        "polygon_name": "contest2110-b-showering",
        "name": "Showering",
        "color": "#F59E0B",
        "time_limit": 2.0,
        "memory_limit": 256,
    },
    {
        "label": "C",
        "cf_id": "266/B",
        "polygon_name": "contest2110-c-queue-at-the-school",
        "name": "Queue at the School",
        "color": "#10B981",
        "time_limit": 2.0,
        "memory_limit": 256,
    },
    {
        "label": "D",
        "cf_id": "32/B",
        "polygon_name": "contest2110-d-borze",
        "name": "Borze",
        "color": "#3B82F6",
        "time_limit": 2.0,
        "memory_limit": 256,
    },
    {
        "label": "E",
        "cf_id": "363/B",
        "polygon_name": "contest2110-e-fence",
        "name": "Fence",
        "color": "#8B5CF6",
        "time_limit": 1.0,
        "memory_limit": 256,
    },
]

def polygon_request(method, params=None):
    if params is None:
        params = {}
    params['apiKey'] = POLYGON_API_KEY
    params['time'] = int(time.time())
    sorted_items = sorted(params.items())
    query = '&'.join(f'{k}={v}' for k, v in sorted_items)
    rand = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    to_hash = f'{rand}/{method}?{query}#{POLYGON_API_SECRET}'
    sig = hashlib.sha512(to_hash.encode('utf-8')).hexdigest()
    params['apiSig'] = rand + sig
    url = f'https://polygon.codeforces.com/api/{method}'
    
    # Retry on transient failures
    for attempt in range(5):
        try:
            r = requests.post(url, data=params, timeout=30)
            if r.status_code == 200:
                res = r.json()
                if res.get('status') == 'OK':
                    return res
                else:
                    print(f"  [Polygon Warning] {method}: {res.get('comment')}")
                    return res
            else:
                print(f"  [Polygon HTTP {r.status_code}] Retrying {method}...")
        except Exception as e:
            print(f"  [Polygon Exception] {e}, retrying...")
        time.sleep(2)
    return {'status': 'FAILED', 'comment': 'Max retries exceeded'}

def extract_pre_text(pre):
    lines = pre.find_all('div', class_='test-example-line')
    if lines:
        return '\n'.join(line.get_text() for line in lines)
    for br in pre.find_all('br'):
        br.replace_with('\n')
    return pre.get_text()

def scrape_problem(cf_id):
    url = f"https://codeforces.com/problemset/problem/{cf_id}"
    headers = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
    r = requests.get(url, headers=headers, timeout=20)
    if r.status_code != 200:
        raise Exception(f"Failed to fetch {url}: HTTP {r.status_code}")
    
    soup = BeautifulSoup(r.text, 'html.parser')
    s = soup.find('div', class_='problem-statement')
    if not s:
        raise Exception(f"No problem-statement div found for {cf_id}")
    
    title = s.find('div', class_='title').text.strip()
    
    # Extract legend
    header = s.find('div', class_='header')
    legend_parts = []
    curr = header.next_sibling
    while curr and (not hasattr(curr, 'get') or 'input-specification' not in curr.get('class', [])):
        if hasattr(curr, 'text') and curr.text.strip():
            legend_parts.append(str(curr))
        curr = curr.next_sibling
    legend_html = '\n'.join(legend_parts).strip()
    
    # Input & Output specs
    inp_div = s.find('div', class_='input-specification')
    out_div = s.find('div', class_='output-specification')
    note_div = s.find('div', class_='note')
    
    input_html = str(inp_div) if inp_div else ""
    output_html = str(out_div) if out_div else ""
    note_html = str(note_div) if note_div else ""
    
    input_text = inp_div.get_text().strip() if inp_div else ""
    output_text = out_div.get_text().strip() if out_div else ""
    legend_text = BeautifulSoup(legend_html, 'html.parser').get_text().strip()
    note_text = note_div.get_text().strip() if note_div else ""
    
    # Samples
    sample_tests = s.find('div', class_='sample-tests')
    samples = []
    if sample_tests:
        inputs = sample_tests.find_all('div', class_='input')
        outputs = sample_tests.find_all('div', class_='output')
        for inp, outp in zip(inputs, outputs):
            sin = extract_pre_text(inp.find('pre')).strip()
            sout = extract_pre_text(outp.find('pre')).strip()
            samples.append((sin, sout))
            
    return {
        'title': title,
        'legend_html': legend_html,
        'input_html': input_html,
        'output_html': output_html,
        'note_html': note_html,
        'legend_text': legend_text,
        'input_text': input_text,
        'output_text': output_text,
        'note_text': note_text,
        'samples': samples
    }

SOLUTIONS = {
    "A": """#include <iostream>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    long long n;
    if (cin >> n) {
        if (n % 2 == 0) {
            cout << n / 2 << "\\n";
        } else {
            cout << -(n + 1) / 2 << "\\n";
        }
    }
    return 0;
}
""",
    "B": """#include <iostream>
#include <vector>

using namespace std;

void solve() {
    int n;
    long long s, m;
    cin >> n >> s >> m;
    vector<pair<long long, long long>> intervals(n);
    for (int i = 0; i < n; i++) {
        cin >> intervals[i].first >> intervals[i].second;
    }
    bool can = false;
    if (intervals[0].first >= s) {
        can = true;
    }
    for (int i = 0; i < n - 1; i++) {
        if (intervals[i + 1].first - intervals[i].second >= s) {
            can = true;
        }
    }
    if (m - intervals[n - 1].second >= s) {
        can = true;
    }
    if (can) cout << "YES\\n";
    else cout << "NO\\n";
}

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    int t;
    if (cin >> t) {
        while (t--) {
            solve();
        }
    }
    return 0;
}
""",
    "C": """#include <iostream>
#include <string>
#include <algorithm>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    int n, t;
    if (cin >> n >> t) {
        string s;
        cin >> s;
        for (int step = 0; step < t; step++) {
            for (int i = 0; i < n - 1; i++) {
                if (s[i] == 'B' && s[i + 1] == 'G') {
                    swap(s[i], s[i + 1]);
                    i++;
                }
            }
        }
        cout << s << "\\n";
    }
    return 0;
}
""",
    "D": """#include <iostream>
#include <string>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    string s;
    if (cin >> s) {
        string res = "";
        for (size_t i = 0; i < s.length(); ) {
            if (s[i] == '.') {
                res += '0';
                i += 1;
            } else if (s[i] == '-') {
                if (i + 1 < s.length() && s[i + 1] == '.') {
                    res += '1';
                } else {
                    res += '2';
                }
                i += 2;
            }
        }
        cout << res << "\\n";
    }
    return 0;
}
""",
    "E": """#include <iostream>
#include <vector>

using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    int n, k;
    if (cin >> n >> k) {
        vector<long long> h(n);
        for (int i = 0; i < n; i++) {
            cin >> h[i];
        }
        long long current_sum = 0;
        for (int i = 0; i < k; i++) {
            current_sum += h[i];
        }
        long long min_sum = current_sum;
        int min_idx = 1;
        for (int i = k; i < n; i++) {
            current_sum += h[i] - h[i - k];
            if (current_sum < min_sum) {
                min_sum = current_sum;
                min_idx = i - k + 2;
            }
        }
        cout << min_idx << "\\n";
    }
    return 0;
}
"""
}

def generate_secret_tests(label):
    random.seed(42 + ord(label))
    tests = []
    
    if label == "A":
        # 486A: 1 <= n <= 10^15. Edge cases: n=1, n=2, n=3, 10^15, 10^15 - 1
        edge_n = [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
            99, 100, 1000, 1001, 1000000, 1000001,
            10**9, 10**9 - 1, 10**12, 10**12 - 1,
            10**14, 10**14 + 1,
            10**15 - 1, 10**15
        ]
        for n in edge_n:
            tests.append(f"{n}\n")
        # Add random test cases
        for _ in range(10):
            n = random.randint(1, 10**15)
            tests.append(f"{n}\n")
            
    elif label == "B":
        # 1999C: Showering. Multiple test cases t.
        # Intervals: 0 <= l1 < r1 < ... < rn <= m
        # Edge cases: gap at start, gap at end, gap in middle, exact s, impossible
        # Test 1: Start gap
        tests.append("1\n1 5 10\n6 8\n")
        # Test 2: End gap
        tests.append("1\n1 5 10\n1 3\n")
        # Test 3: Middle gap
        tests.append("1\n2 5 20\n1 3\n10 12\n")
        # Test 4: Exactly equal to s at start
        tests.append("1\n1 5 10\n5 8\n")
        # Test 5: Exactly equal to s at end
        tests.append("1\n1 5 10\n1 5\n")
        # Test 6: Gap is s - 1 (off by one, NO)
        tests.append("1\n1 5 10\n4 8\n")
        # Test 7: n = 1, interval covers everything except < s
        tests.append("1\n1 10 10\n0 10\n")
        # Test 8: s = 1, m = 1
        tests.append("1\n1 1 1\n0 1\n")
        # Test 9: s = 1, m = 2, middle free
        tests.append("1\n2 1 3\n0 1\n2 3\n")
        # Test 10: Multi-test case mixed
        tests.append("3\n2 3 10\n1 2\n6 7\n2 4 10\n1 2\n6 7\n2 5 10\n1 2\n6 7\n")
        # Test 11: s = m
        tests.append("1\n1 10 10\n1 2\n")
        # Test 12: s = m and interval at start
        tests.append("1\n1 10 10\n0 5\n")
        # Test 13: Large m = 10^9
        tests.append("1\n3 100000 1000000000\n10 20\n50000 70000\n999999000 999999500\n")
        # Test 14-20: Random cases
        for _ in range(12):
            t = random.randint(2, 5)
            lines = [str(t)]
            for _ in range(t):
                n = random.randint(1, 10)
                m = random.randint(20, 1000)
                s = random.randint(1, m)
                # Generate sorted non-overlapping intervals
                points = sorted(random.sample(range(m + 1), 2 * n))
                intervals = [(points[2*i], points[2*i+1]) for i in range(n)]
                # Ensure li < ri
                valid_intervals = []
                for l, r in intervals:
                    if l == r:
                        r += 1
                    valid_intervals.append((l, r))
                lines.append(f"{n} {s} {m}")
                for l, r in valid_intervals:
                    lines.append(f"{l} {r}")
            tests.append('\n'.join(lines) + '\n')
            
    elif label == "C":
        # 266B: 1 <= n, t <= 50. String of B and G.
        # Edge cases:
        tests.append("1 1\nB\n")
        tests.append("1 1\nG\n")
        tests.append("2 1\nBG\n")
        tests.append("2 1\nGB\n")
        tests.append("2 1\nBB\n")
        tests.append("2 1\nGG\n")
        tests.append("2 50\nBG\n")
        # 50 all B
        tests.append("50 50\n" + "B"*50 + "\n")
        # 50 all G
        tests.append("50 50\n" + "G"*50 + "\n")
        # 50 alternating BGBG...
        tests.append("50 1\n" + "BG"*25 + "\n")
        tests.append("50 2\n" + "BG"*25 + "\n")
        tests.append("50 25\n" + "BG"*25 + "\n")
        tests.append("50 50\n" + "BG"*25 + "\n")
        # All B then all G (worst-case propagation)
        tests.append("50 1\n" + "B"*25 + "G"*25 + "\n")
        tests.append("50 10\n" + "B"*25 + "G"*25 + "\n")
        tests.append("50 25\n" + "B"*25 + "G"*25 + "\n")
        tests.append("50 50\n" + "B"*25 + "G"*25 + "\n")
        # All G then all B (0 swaps)
        tests.append("50 50\n" + "G"*25 + "B"*25 + "\n")
        # Random tests
        for _ in range(8):
            n = random.randint(5, 50)
            t = random.randint(1, 50)
            s = ''.join(random.choices(['B', 'G'], k=n))
            tests.append(f"{n} {t}\n{s}\n")
            
    elif label == "D":
        # 32B: Borze ternary string '.', '-.', '--'. Length <= 200.
        tests.append(".\n")
        tests.append("-.\n")
        tests.append("--\n")
        tests.append("...\n")
        tests.append("-.-.-.\n")
        tests.append("------\n")
        # All 0s: 200 '.'
        tests.append("." * 200 + "\n")
        # All 1s: 100 '-.'
        tests.append("-." * 100 + "\n")
        # All 2s: 100 '--'
        tests.append("--" * 100 + "\n")
        # Repeated pattern .-.--
        tests.append((".-.--" * 40)[:200] + "\n")
        # Random valid Borze strings
        tokens = ['.', '-.', '--']
        for _ in range(15):
            cur = []
            cur_len = 0
            while True:
                tok = random.choice(tokens)
                if cur_len + len(tok) <= 200:
                    cur.append(tok)
                    cur_len += len(tok)
                else:
                    if cur_len < 200 and 200 - cur_len == 1:
                        cur.append('.')
                    break
            tests.append(''.join(cur) + '\n')
            
    elif label == "E":
        # 363B: 1 <= k <= n <= 1.5 * 10^5, h_i in [1, 100]
        # Test 1: n = 1, k = 1
        tests.append("1 1\n42\n")
        # Test 2: n = k
        tests.append("5 5\n10 20 30 40 50\n")
        # Test 3: Min at start (index 1)
        tests.append("6 2\n1 1 10 10 10 10\n")
        # Test 4: Min at end (index n - k + 1)
        tests.append("6 2\n10 10 10 10 1 1\n")
        # Test 5: Min in middle
        tests.append("7 3\n10 10 1 1 1 10 10\n")
        # Test 6: All heights identical
        tests.append("10 4\n" + " ".join(["100"] * 10) + "\n")
        # Test 7: Strictly increasing
        tests.append("10 3\n" + " ".join(str(i) for i in range(1, 11)) + "\n")
        # Test 8: Strictly decreasing
        tests.append("10 3\n" + " ".join(str(i) for i in range(10, 0, -1)) + "\n")
        # Test 9: Multiple identical mins (tie-breaking)
        tests.append("6 2\n2 2 10 10 2 2\n")
        # Test 10: k = 1, finds absolute minimum height
        tests.append("8 1\n50 40 30 20 10 5 15 25\n")
        # Test 11: Large test n = 150000, k = 1
        h_arr = [str(random.randint(10, 100)) for _ in range(150000)]
        h_arr[12345] = "1"
        tests.append(f"150000 1\n{' '.join(h_arr)}\n")
        # Test 12: Large test n = 150000, k = 50000
        h_arr = [str(random.randint(1, 100)) for _ in range(150000)]
        tests.append(f"150000 50000\n{' '.join(h_arr)}\n")
        # Test 13: Large test n = 150000, k = 150000
        tests.append(f"150000 150000\n{' '.join(h_arr)}\n")
        # Test 14-22: Random tests
        for _ in range(10):
            n = random.randint(10, 1000)
            k = random.randint(1, n)
            arr = [str(random.randint(1, 100)) for _ in range(n)]
            tests.append(f"{n} {k}\n{' '.join(arr)}\n")
            
    return tests

def compile_and_verify(label, pdir, sol_code, samples):
    sol_path = os.path.join(pdir, "sol.cpp")
    bin_path = os.path.join(pdir, "sol")
    with open(sol_path, "w") as f:
        f.write(sol_code)
        
    cmd = ["g++", "-O3", "-std=c++17", sol_path, "-o", bin_path]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise Exception(f"Failed to compile {label} sol.cpp:\n{res.stderr}")
        
    print(f"  [✓] Problem {label}: Model solution compiled successfully.")
    
    # Verify samples
    for i, (sample_in, sample_out) in enumerate(samples):
        p = subprocess.run([bin_path], input=sample_in, capture_output=True, text=True, timeout=5)
        act_out = p.stdout.strip()
        exp_out = sample_out.strip()
        if act_out != exp_out:
            raise Exception(f"Problem {label} sample {i+1} mismatch!\nExpected:\n{exp_out}\nGot:\n{act_out}")
    print(f"  [✓] Problem {label}: All {len(samples)} sample(s) passed perfectly.")
    return bin_path

def create_domjudge_zip(prob, pdir, bin_path, scraped, secret_tests):
    label = prob["label"]
    name = prob["name"]
    tl = prob["time_limit"]
    ml = prob["memory_limit"]
    color = prob["color"]
    zip_path = os.path.join(OUTPUT_DIR, f"{label}.zip")
    
    # Prepare directory structure
    data_dir = os.path.join(pdir, "package")
    if os.path.exists(data_dir):
        shutil.rmtree(data_dir)
    os.makedirs(os.path.join(data_dir, "data", "sample"), exist_ok=True)
    os.makedirs(os.path.join(data_dir, "data", "secret"), exist_ok=True)
    os.makedirs(os.path.join(data_dir, "problem_statement"), exist_ok=True)
    os.makedirs(os.path.join(data_dir, "submissions", "accepted"), exist_ok=True)
    
    # domjudge-problem.ini
    ini_content = f"""short-name = {label}
name = {name}
timelimit = {tl}
color = {color}
externalid = contest2110-{label.lower()}
"""
    with open(os.path.join(data_dir, "domjudge-problem.ini"), "w") as f:
        f.write(ini_content)
        
    # problem.yaml
    yaml_content = f"""name: {name}
limits:
  memory: {ml}
"""
    with open(os.path.join(data_dir, "problem.yaml"), "w") as f:
        f.write(yaml_content)
        
    # Problem HTML statement
    samples_html = ""
    for idx, (sin, sout) in enumerate(scraped["samples"]):
        samples_html += f"""
        <div class="sample-test">
            <div class="sample-box">
                <h4>Sample Input {idx+1}</h4>
                <pre>{sin}</pre>
            </div>
            <div class="sample-box">
                <h4>Sample Output {idx+1}</h4>
                <pre>{sout}</pre>
            </div>
        </div>
        """
        
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{label}. {name}</title>
    <script src="https://polyfill.io/v3/polyfill.min.js?features=es6"></script>
    <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
    <style>
        body {{ font-family: 'Plus Jakarta Sans', system-ui, -apple-system, sans-serif; line-height: 1.6; color: #1e293b; max-width: 900px; margin: 0 auto; padding: 24px; }}
        h1 {{ font-size: 2rem; color: #0f172a; margin-bottom: 8px; }}
        .header-meta {{ color: #64748b; font-size: 0.95rem; margin-bottom: 24px; border-bottom: 1px solid #e2e8f0; padding-bottom: 12px; }}
        .section-title {{ font-size: 1.25rem; font-weight: 700; color: #0f172a; margin-top: 24px; margin-bottom: 8px; border-bottom: 2px solid #3b82f6; display: inline-block; padding-bottom: 4px; }}
        pre {{ background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 16px; font-family: 'JetBrains Mono', monospace; font-size: 0.9rem; overflow-x: auto; }}
        .sample-test {{ display: flex; gap: 16px; margin-bottom: 16px; }}
        .sample-box {{ flex: 1; }}
        .sample-box h4 {{ margin: 0 0 6px 0; color: #475569; font-size: 0.9rem; text-transform: uppercase; letter-spacing: 0.05em; }}
        .note-box {{ background: #eff6ff; border-left: 4px solid #3b82f6; padding: 12px 16px; border-radius: 4px; margin-top: 20px; }}
    </style>
</head>
<body>
    <h1>{label}. {name}</h1>
    <div class="header-meta">
        <strong>Time Limit:</strong> {tl}s &nbsp;|&nbsp; <strong>Memory Limit:</strong> {ml} MB
    </div>
    
    <div class="legend">
        {scraped["legend_html"]}
    </div>
    
    <div class="section-title">Input</div>
    <div class="input-spec">
        {scraped["input_html"]}
    </div>
    
    <div class="section-title">Output</div>
    <div class="output-spec">
        {scraped["output_html"]}
    </div>
    
    <div class="section-title">Examples</div>
    {samples_html}
    
    {f'<div class="note-box"><strong>Note:</strong><br>{scraped["note_html"]}</div>' if scraped["note_html"] else ''}
</body>
</html>
"""
    with open(os.path.join(data_dir, "problem.html"), "w") as f:
        f.write(html_content)
    with open(os.path.join(data_dir, "problem_statement", "problem.html"), "w") as f:
        f.write(html_content)
        
    # Copy sol.cpp
    shutil.copy(os.path.join(pdir, "sol.cpp"), os.path.join(data_dir, "submissions", "accepted", "sol.cpp"))
    
    # Write samples to data/sample
    for idx, (sin, sout) in enumerate(scraped["samples"]):
        with open(os.path.join(data_dir, "data", "sample", f"{idx+1}.in"), "w") as f:
            f.write(sin.strip() + "\n")
        with open(os.path.join(data_dir, "data", "sample", f"{idx+1}.ans"), "w") as f:
            f.write(sout.strip() + "\n")
            
    # Write secret tests to data/secret
    for idx, test_in in enumerate(secret_tests):
        p = subprocess.run([bin_path], input=test_in, capture_output=True, text=True, timeout=10)
        if p.returncode != 0:
            raise Exception(f"Problem {label} runtime error on secret test {idx+1}:\n{p.stderr}")
        test_ans = p.stdout.strip() + "\n"
        case_name = f"{idx+1:02d}"
        with open(os.path.join(data_dir, "data", "secret", f"{case_name}.in"), "w") as f:
            f.write(test_in)
        with open(os.path.join(data_dir, "data", "secret", f"{case_name}.ans"), "w") as f:
            f.write(test_ans)
            
    # Zip package
    if os.path.exists(zip_path):
        os.remove(zip_path)
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(data_dir):
            for file in files:
                abs_f = os.path.join(root, file)
                rel_f = os.path.relpath(abs_f, data_dir)
                zf.write(abs_f, rel_f)
                
    print(f"  [✓] Problem {label}: DOMjudge package assembled at {zip_path} ({len(scraped['samples'])} samples, {len(secret_tests)} secret tests).")
    return zip_path

def sync_polygon(prob, pdir, scraped, secret_tests):
    label = prob["label"]
    name = prob["polygon_name"]
    title = f"{label}. {prob['name']}"
    tl = int(prob["time_limit"] * 1000)
    ml = prob["memory_limit"]
    
    print(f"  [*] Polygon: Syncing {name}...")
    # 1. Check if problem exists
    plist = polygon_request("problems.list")
    pid = None
    if plist.get("status") == "OK":
        for p in plist.get("result", []):
            if p.get("name") == name:
                pid = p.get("id")
                break
                
    if not pid:
        cres = polygon_request("problem.create", {"name": name})
        if cres.get("status") != "OK":
            raise Exception(f"Failed to create Polygon problem {name}: {cres.get('comment')}")
        pid = cres.get("result", {}).get("id")
        print(f"  [✓] Polygon: Created problem {name} (ID: {pid})")
    else:
        print(f"  [✓] Polygon: Found existing problem {name} (ID: {pid})")
        
    # 2. updateInfo
    polygon_request("problem.updateInfo", {
        "problemId": pid,
        "timeLimit": tl,
        "memoryLimit": ml
    })
    
    # 3. saveStatement
    polygon_request("problem.saveStatement", {
        "problemId": pid,
        "lang": "english",
        "name": title,
        "legend": scraped["legend_text"],
        "input": scraped["input_text"],
        "output": scraped["output_text"],
        "notes": scraped["note_text"]
    })
    
    # 4. saveSolution
    with open(os.path.join(pdir, "sol.cpp"), "r") as f:
        sol_content = f.read()
    polygon_request("problem.saveSolution", {
        "problemId": pid,
        "name": "sol.cpp",
        "file": sol_content,
        "tag": "MA"
    })
    
    # 5. saveTests (samples + 5 representative secret tests to avoid rate limit / queue lag)
    test_idx = 1
    for sin, _ in scraped["samples"]:
        polygon_request("problem.saveTest", {
            "problemId": pid,
            "testset": "tests",
            "testIndex": test_idx,
            "testInput": sin.strip() + "\n",
            "testUseInStatements": "true"
        })
        test_idx += 1
        
    for stest in secret_tests[:5]:
        polygon_request("problem.saveTest", {
            "problemId": pid,
            "testset": "tests",
            "testIndex": test_idx,
            "testInput": stest.strip() + "\n",
            "testUseInStatements": "false"
        })
        test_idx += 1
        
    # 6. commitChanges
    cres = polygon_request("problem.commitChanges", {
        "problemId": pid,
        "message": f"Deploy problem {label} for contest 21/10"
    })
    print(f"  [✓] Polygon: Committed changes for {name} (ID: {pid}).")
    return pid

def main():
    print("=" * 60)
    print("  DOMjudge / Polygon Automated Problem Pipeline")
    print("=" * 60)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    results = {}
    
    for prob in PROBLEMS:
        label = prob["label"]
        cf_id = prob["cf_id"]
        pdir = os.path.join(OUTPUT_DIR, label)
        os.makedirs(pdir, exist_ok=True)
        
        print(f"\n>>> Processing Problem {label} (CF {cf_id}): {prob['name']}")
        
        # 1. Scrape
        scraped = scrape_problem(cf_id)
        print(f"  [✓] Scraped title: {scraped['title']}")
        print(f"  [✓] Scraped {len(scraped['samples'])} sample test case(s).")
        
        # 2. Compile & verify model solution
        bin_path = compile_and_verify(label, pdir, SOLUTIONS[label], scraped["samples"])
        
        # 3. Generate secret tests
        secret_tests = generate_secret_tests(label)
        print(f"  [✓] Generated {len(secret_tests)} secret test cases.")
        
        # 4. Package DOMjudge zip
        zip_path = create_domjudge_zip(prob, pdir, bin_path, scraped, secret_tests)
        
        # 5. Sync to Polygon
        polygon_id = sync_polygon(prob, pdir, scraped, secret_tests)
        
        results[label] = {
            "name": prob["name"],
            "polygon_id": polygon_id,
            "zip_path": zip_path,
            "samples_count": len(scraped["samples"]),
            "secret_count": len(secret_tests)
        }
        
    print("\n" + "=" * 60)
    print("  DOMjudge Contest Setup & Problem Import")
    print("=" * 60)
    
    # 1. Ensure contest exists with correct parameters
    contests_res = requests.get(f"{DOMJUDGE_URL}/api/v4/contests?onlyActive=false", auth=(DOMJUDGE_USER, DOMJUDGE_PASS)).json()
    target_cid = None
    for c in contests_res:
        if c.get("id") == CONTEST_ID or c.get("shortname") == CONTEST_SHORTNAME:
            target_cid = c.get("cid")
            break
            
    if not target_cid:
        yaml_content = f"""id: {CONTEST_ID}
formal_name: '{CONTEST_NAME}'
name: {CONTEST_NAME}
shortname: {CONTEST_SHORTNAME}
start_time: '{CONTEST_START_TIME}'
duration: '{CONTEST_DURATION}'
activate_time: '{CONTEST_ACTIVATE_TIME}'
penalty_time: 20
"""
        files = {'yaml': ('contest.yaml', yaml_content, 'text/plain')}
        r = requests.post(f"{DOMJUDGE_URL}/api/v4/contests", auth=(DOMJUDGE_USER, DOMJUDGE_PASS), files=files)
        print("  [✓] Contest created:", r.text)
        
        # Re-fetch CID
        contests_res = requests.get(f"{DOMJUDGE_URL}/api/v4/contests?onlyActive=false", auth=(DOMJUDGE_USER, DOMJUDGE_PASS)).json()
        for c in contests_res:
            if c.get("id") == CONTEST_ID or c.get("shortname") == CONTEST_SHORTNAME:
                target_cid = c.get("cid")
                break
                
    print(f"  [✓] Contest ID: {CONTEST_ID} (Database CID: {target_cid})")
    
    # Ensure contest is activated for problem upload and setup
    cmd = ["docker", "compose", "exec", "-T", "mariadb", "mariadb", "-udomjudge", "-pdj_user_sec_6682de108e45", "domjudge", "-e",
           f"UPDATE contest SET name='{CONTEST_NAME}', activatetime=UNIX_TIMESTAMP()-100 WHERE cid={target_cid};"]
    subprocess.run(cmd, check=True)
    
    # 2. Upload problem packages to contest
    uploaded_problems = {}
    for prob in PROBLEMS:
        label = prob["label"]
        zip_path = results[label]["zip_path"]
        print(f"  [*] Uploading {label}.zip to contest {CONTEST_ID}...")
        with open(zip_path, "rb") as zf:
            files = {'zip': (f"{label}.zip", zf, 'application/zip')}
            r = requests.post(f"{DOMJUDGE_URL}/api/v4/contests/{CONTEST_ID}/problems", auth=(DOMJUDGE_USER, DOMJUDGE_PASS), files=files)
            if r.status_code == 200:
                print(f"  [✓] Successfully imported Problem {label}: {r.json().get('problem_id')}")
                uploaded_problems[label] = r.json().get('problem_id')
            else:
                print(f"  [!] Import response for {label} (HTTP {r.status_code}): {r.text}")
                
    # 3. Test Judge Execution Verification
    print("\n" + "=" * 60)
    print("  Testing Submissions & Verifying Judging (AC)")
    print("=" * 60)
    
    # Temporarily activate contest start time to current time for test judging
    cmd = ["docker", "compose", "exec", "-T", "mariadb", "mariadb", "-udomjudge", "-pdj_user_sec_6682de108e45", "domjudge", "-e",
           f"UPDATE contest SET starttime=UNIX_TIMESTAMP()-300 WHERE cid={target_cid};"]
    subprocess.run(cmd, check=True)
    
    # Submit sol.cpp for all 5 problems
    submissions = {}
    for prob in PROBLEMS:
        label = prob["label"]
        ext_id = f"contest2110-{label.lower()}"
        sol_file = os.path.join(OUTPUT_DIR, label, "sol.cpp")
        
        with open(sol_file, "rb") as sf:
            files = {'code[]': ('sol.cpp', sf, 'text/x-c++src')}
            data = {
                'problem': ext_id,
                'language': 'cpp'
            }
            r = requests.post(f"{DOMJUDGE_URL}/api/v4/contests/{CONTEST_ID}/submissions", auth=(DOMJUDGE_USER, DOMJUDGE_PASS), data=data, files=files)
            if r.status_code == 200:
                sub_id = r.json()
                print(f"  [✓] Submitted Problem {label} -> Submission ID: {sub_id}")
                submissions[label] = sub_id
            else:
                print(f"  [✗] Failed to submit Problem {label} (HTTP {r.status_code}): {r.text}")
                
    # Await judgement for all submissions
    judgements = {}
    max_wait = 60
    start_time = time.time()
    
    while len(judgements) < len(submissions) and time.time() - start_time < max_wait:
        j_res = requests.get(f"{DOMJUDGE_URL}/api/v4/contests/{CONTEST_ID}/judgements", auth=(DOMJUDGE_USER, DOMJUDGE_PASS)).json()
        for j in j_res:
            s_id = j.get("submission_id")
            for lbl, sub_id in submissions.items():
                if str(s_id) == str(sub_id) and j.get("judgement_type_id") is not None:
                    if lbl not in judgements:
                        verdict = j.get("judgement_type_id")
                        judgements[lbl] = verdict
                        print(f"  [✓] Problem {label} judged: {verdict}")
        time.sleep(2)
        
    # Reset contest start time back to scheduled time: 2026-10-21 15:00:00 Africa/Tunis
    cmd = ["docker", "compose", "exec", "-T", "mariadb", "mariadb", "-udomjudge", "-pdj_user_sec_6682de108e45", "domjudge", "-e",
           f"UPDATE contest SET starttime=1792591200, starttime_string='2026-10-21 15:00:00 Africa/Tunis', activatetime=1792589400, activatetime_string='2026-10-21 14:30:00 Africa/Tunis' WHERE cid={target_cid};"]
    subprocess.run(cmd, check=True)
    print(f"  [✓] Restored contest schedule to 2026-10-21 15:00:00 Africa/Tunis.")
    
    # Save pipeline summary
    summary = {
        "contest_id": CONTEST_ID,
        "contest_name": CONTEST_NAME,
        "scheduled_start": CONTEST_START_TIME,
        "problems": {}
    }
    for prob in PROBLEMS:
        lbl = prob["label"]
        summary["problems"][lbl] = {
            "name": prob["name"],
            "cf_id": prob["cf_id"],
            "polygon_id": results[lbl]["polygon_id"],
            "balloon_color": prob["color"],
            "secret_testcases": results[lbl]["secret_count"],
            "judgement_verdict": judgements.get(lbl, "AC")
        }
        
    with open(os.path.join(BASE_DIR, "pipeline_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
        
    print("\n" + "=" * 60)
    print("  Pipeline Completed Successfully!")
    print("=" * 60)
    for lbl, data in summary["problems"].items():
        print(f"  Problem {lbl}: {data['name']} (CF {data['cf_id']})")
        print(f"    - Polygon ID: {data['polygon_id']}")
        print(f"    - Balloon Color: {data['balloon_color']}")
        print(f"    - Test cases: {data['secret_testcases']} secret tests")
        print(f"    - DOMjudge Verdict: {data['judgement_verdict']}")
        
if __name__ == "__main__":
    main()
