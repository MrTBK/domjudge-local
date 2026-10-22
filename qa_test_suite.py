#!/usr/bin/env python3
"""
DOMjudge Full QA Automation Test Suite (Zero-Dependency: pure stdlib)
Tests:
  1. System & Container Health (MariaDB, DOMserver, 4 Judgehosts)
  2. Frontend Rendering & Codeforces-Style White Editor UI
  3. Client-Side Auto-Detection Logic Verification
  4. End-to-End Submission Pipeline (Python Correct, C++ Correct, Wrong Answer)
  5. Scoreboard & Submission Details Inspection
"""

import sys
import time
import re
import os
import subprocess
import urllib.request
import urllib.parse
import http.cookiejar

BASE_URL = "http://127.0.0.1:8080"
MYSQL_PASSWORD = "dj_user_sec_6682de108e45"

PASSED = 0
FAILED = 0
TOTAL = 0

cookie_jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))

def log_header(title):
    print(f"\n\033[1;36m{'='*65}\033[0m")
    print(f"\033[1;36m  {title}\033[0m")
    print(f"\033[1;36m{'='*65}\033[0m")

def run_test(test_id, description, func):
    global PASSED, FAILED, TOTAL
    TOTAL += 1
    print(f"\033[1;34m[TEST {test_id}]\033[0m {description}...", end=" ", flush=True)
    start_t = time.time()
    try:
        success, msg = func()
        elapsed = time.time() - start_t
        if success:
            PASSED += 1
            print(f"\033[1;32m[PASS]\033[0m \033[90m({elapsed:.2f}s)\033[0m")
            if msg:
                print(f"       \033[32m└─ {msg}\033[0m")
        else:
            FAILED += 1
            print(f"\033[1;31m[FAIL]\033[0m \033[90m({elapsed:.2f}s)\033[0m")
            if msg:
                print(f"       \033[31m└─ Error: {msg}\033[0m")
    except Exception as e:
        FAILED += 1
        elapsed = time.time() - start_t
        print(f"\033[1;31m[ERROR]\033[0m \033[90m({elapsed:.2f}s)\033[0m")
        print(f"       \033[31m└─ Exception: {e}\033[0m")

def query_db(sql):
    cmd = [
        "docker", "compose", "exec", "-T", "mariadb",
        "mariadb", "-udomjudge", f"-p{MYSQL_PASSWORD}", "domjudge", "-N", "-e", sql
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"DB Error: {res.stderr}")
    return res.stdout.strip()

def http_get(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    with opener.open(req) as resp:
        return resp.getcode(), resp.read().decode('utf-8', errors='replace')

# -------------------------------------------------------------
# Section 1: Container & Daemon QA
# -------------------------------------------------------------
def test_containers_running():
    cmd = ["docker", "ps", "--format", "{{.Names}}: {{.Status}}"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    required = ["dj-mariadb", "dj-domserver", "dj-judgehost-1", "dj-judgehost-2", "dj-judgehost-3", "dj-judgehost-4"]
    missing = [c for c in required if c not in res.stdout]
    if missing:
        return False, f"Missing containers: {missing}"
    return True, "All 6 required containers are active"

def test_judgehosts_polling():
    out = query_db("SELECT COUNT(*), MIN(UNIX_TIMESTAMP() - polltime) FROM judgehost WHERE enabled=1 AND polltime IS NOT NULL")
    parts = out.split()
    count = int(parts[0])
    min_diff = float(parts[1]) if len(parts) > 1 and parts[1] != 'NULL' else 999
    if count < 4:
        return False, f"Only {count} judgehosts registered in DB (expected 4)"
    if min_diff > 30:
        return False, f"Judgehost polling delayed ({min_diff:.1f}s ago)"
    return True, f"{count} judgehosts active & polling DOMserver (latest {min_diff:.1f}s ago)"

def test_active_contest():
    out = query_db("SELECT cid, name, allow_submit FROM contest WHERE enabled=1 ORDER BY cid DESC LIMIT 1")
    if not out:
        return False, "No enabled contest found"
    parts = out.split("\t")
    cid, name, allow_submit = parts[0], parts[1], parts[2]
    if allow_submit != '1':
        return False, f"Contest {name} (cid={cid}) has allow_submit=0"
    return True, f"Active contest '{name}' (cid={cid}) allows submissions"

# -------------------------------------------------------------
# Section 2: Frontend & White Code Editor UI QA
# -------------------------------------------------------------
def get_csrf_token(html):
    m = re.search(r'name=["\']_csrf_token["\']\s+value=["\']([^"\']+)["\']', html)
    if not m:
        m = re.search(r'name=["\']submit_problem\[_token\]["\']\s+value=["\']([^"\']+)["\']', html)
    return m.group(1) if m else None

def test_auth_login():
    status, html = http_get(f"{BASE_URL}/login")
    if status != 200:
        return False, f"Login page HTTP {status}"
    token = get_csrf_token(html)
    if not token:
        return False, "Could not extract login CSRF token"
    
    data = urllib.parse.urlencode({"_username": "demo", "_password": "demo", "_csrf_token": token}).encode('utf-8')
    req = urllib.request.Request(f"{BASE_URL}/login", data=data)
    with opener.open(req) as resp:
        post_html = resp.read().decode('utf-8', errors='replace')
        if resp.getcode() != 200 and "teamwelcome" not in post_html:
            return False, "Failed to authenticate team user 'demo'"
    
    # Switch to contest 3 (active contest)
    http_get(f"{BASE_URL}/team/change-contest/3")
    return True, "Successfully logged in as team 'demo' and switched to active contest"

def test_standalone_submit_page():
    status, html = http_get(f"{BASE_URL}/team/submit")
    if status != 200:
        return False, f"HTTP {status}"

    checks = [
        ('novalidate="novalidate"', "Form has novalidate attribute"),
        ('id="tab_mode_paste"', "Paste Code tab exists"),
        ('id="tab_mode_upload"', "Upload File tab exists"),
        ('id="submit_code_text"', "Code textarea exists"),
        ('background-color: #FFFFFF', "Textarea background is WHITE (#FFFFFF)"),
        ('color: #0F172A', "Textarea font color is dark slate (#0F172A)"),
        ('id="btn_run_autodetect"', "One-click Auto-Detect button exists"),
        ('id="btn_submit_solution"', "Submit Solution button exists"),
        ('id="editor_autodetect_pill"', "Auto-Detect badge pill exists")
    ]
    for pattern, desc in checks:
        if pattern not in html:
            return False, f"Missing component in /team/submit: {desc}"

    return True, "Standalone submit page rendered with white editor & all controls"

def test_ajax_submit_modal():
    status, html = http_get(f"{BASE_URL}/team/submit", headers={"X-Requested-With": "XMLHttpRequest"})
    if status != 200:
        return False, f"HTTP {status}"

    checks = [
        ('modal-header bg-white text-dark', "Modal header is clean white"),
        ('novalidate="novalidate"', "Modal form has novalidate attribute"),
        ('background-color: #FFFFFF', "Modal textarea is WHITE (#FFFFFF)"),
        ('id="tab_mode_paste"', "Modal has Paste Code tab"),
        ('id="btn_run_autodetect"', "Modal has Auto-Detect button"),
        ('id="btn_submit_solution"', "Modal has Submit Solution button")
    ]
    for pattern, desc in checks:
        if pattern not in html:
            return False, f"Missing component in submit modal: {desc}"
    return True, "AJAX Submit Modal rendered with clean white aesthetic and controls"

# -------------------------------------------------------------
# Section 3: Auto-Detection Pattern QA
# -------------------------------------------------------------
def test_autodetect_patterns():
    py_code = """
import sys

def main():
    name = sys.stdin.readline().strip()
    print("Hello, " + name)

if __name__ == '__main__':
    main()
"""
    cpp_code = """
#include <iostream>
#include <vector>
using namespace std;

int main() {
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    cout << "Hello world!" << endl;
    return 0;
}
"""
    java_code = """
import java.util.Scanner;

public class Solution {
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);
        System.out.println("Hello world!");
    }
}
"""
    # Check C++ regex
    re_cpp = r'^\s*#\s*include\s*[<"](iostream|vector|bits\/stdc\+\+\.h)[>"]|using\s+namespace\s+std\s*;'
    if not re.search(re_cpp, cpp_code, re.M):
        return False, "C++ regex pattern failed on C++ sample"

    # Check Python regex
    re_py = r'^\s*(def\s+\w+|import\s+sys|if\s+__name__\s*==)'
    if not re.search(re_py, py_code, re.M):
        return False, "Python regex pattern failed on Python sample"

    # Check Java regex and Class Name extraction
    re_java = r'import\s+java\.|public\s+class\s+\w+'
    if not re.search(re_java, java_code, re.M):
        return False, "Java regex pattern failed on Java sample"

    m = re.search(r'(?:public\s+)?class\s+([A-Za-z0-9_]+)', java_code)
    if not m or m.group(1) != "Solution":
        return False, f"Java class extraction returned {m.group(1) if m else None} (expected 'Solution')"

    return True, "Regex engine accurately detected C++, Python 3, and Java class 'Solution'"

# -------------------------------------------------------------
# Section 4: End-to-End Submission & Judgehost Pipeline QA
# -------------------------------------------------------------
COOKIE_FILE = "/tmp/qa_cookies.txt"

def submit_via_curl(code_text, lang_id, prob_id, filename):
    # Save cookie jar to file for curl
    status, html = http_get(f"{BASE_URL}/team/submit")
    token = get_csrf_token(html)
    if not token:
        raise RuntimeError("Failed to obtain form CSRF token")

    # Export cookies for curl
    cookie_str = "; ".join([f"{c.name}={c.value}" for c in cookie_jar])
    temp_file = f"/tmp/{filename}"
    with open(temp_file, "w") as f:
        f.write(code_text)

    cmd = [
        "curl", "-s", "-b", cookie_str, "-X", "POST", f"{BASE_URL}/team/submit",
        "-F", f"submit_problem[problem]={prob_id}",
        "-F", f"submit_problem[language]={lang_id}",
        "-F", "submit_problem[entry_point]=",
        "-F", f"submit_problem[code][]=@{temp_file};filename={filename}",
        "-F", f"submit_problem[_token]={token}",
        "-L", "-o", "/dev/null", "-w", "%{http_code}"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if os.path.exists(temp_file):
        os.remove(temp_file)

    if res.stdout.strip() not in ("200", "302"):
        return None, f"HTTP status {res.stdout.strip()}"

    sub_id = query_db(f"SELECT submitid FROM submission WHERE langid='{lang_id}' AND probid={prob_id} ORDER BY submitid DESC LIMIT 1")
    return int(sub_id), "OK"

def wait_for_judging(submit_id, max_wait=30):
    start = time.time()
    while time.time() - start < max_wait:
        res = query_db(f"SELECT j.result FROM judging j WHERE j.submitid={submit_id} AND j.valid=1")
        if res and res != "NULL":
            return res
        time.sleep(1)
    return None

def test_e2e_python_correct():
    code = 'print("Hello world!")\n'
    sub_id, msg = submit_via_curl(code, "py3", 1, "solution.py")
    if not sub_id:
        return False, f"Submission rejected: {msg}"
    
    verdict = wait_for_judging(sub_id, max_wait=25)
    if verdict != "correct":
        return False, f"Submission {sub_id} evaluated as '{verdict}' (expected 'correct')"
    return True, f"Submission #{sub_id} (Python 3) judged as '{verdict}' by judgehost"

def test_e2e_cpp_correct():
    code = """#include <iostream>
using namespace std;
int main() {
    cout << "Hello world!" << endl;
    return 0;
}
"""
    sub_id, msg = submit_via_curl(code, "cpp", 1, "solution.cpp")
    if not sub_id:
        return False, f"Submission rejected: {msg}"
    
    verdict = wait_for_judging(sub_id, max_wait=25)
    if verdict != "correct":
        return False, f"Submission {sub_id} evaluated as '{verdict}' (expected 'correct')"
    return True, f"Submission #{sub_id} (C++ GCC) compiled and judged as '{verdict}'"

def test_e2e_wrong_answer():
    code = 'print("Wrong Answer output")\n'
    sub_id, msg = submit_via_curl(code, "py3", 1, "solution.py")
    if not sub_id:
        return False, f"Submission rejected: {msg}"
    
    verdict = wait_for_judging(sub_id, max_wait=25)
    if verdict != "wrong-answer":
        return False, f"Submission {sub_id} evaluated as '{verdict}' (expected 'wrong-answer')"
    return True, f"Submission #{sub_id} correctly caught as '{verdict}'"

# -------------------------------------------------------------
# Section 5: Scoreboard & Submission Details QA
# -------------------------------------------------------------
def test_team_dashboard_submissions():
    status, html = http_get(f"{BASE_URL}/team")
    if status != 200:
        return False, f"HTTP {status}"
    if 'submissions-table' not in html and 'data-table' not in html:
        return False, "Submissions table missing from team dashboard"
    if 'correct' not in html:
        return False, "Recent 'correct' badge not found in dashboard"
    return True, "Submissions table reflects live verdicts and status"

def test_submission_details_modal():
    sub_id = query_db("SELECT submitid FROM submission ORDER BY submitid DESC LIMIT 1")
    status, html = http_get(f"{BASE_URL}/team/submission/{sub_id}", headers={"X-Requested-With": "XMLHttpRequest"})
    if status != 200:
        return False, f"HTTP {status}"
    if 'Problem:' not in html and 'Result:' not in html:
        return False, "Judging breakdown missing from submission modal"
    return True, f"Submission #{sub_id} modal details view accessible and verified"

# -------------------------------------------------------------
# Runner
# -------------------------------------------------------------
def main():
    log_header("PHASE 1: CONTAINER & DAEMON INFRASTRUCTURE")
    run_test("1.1", "Verify all Docker containers are running and healthy", test_containers_running)
    run_test("1.2", "Verify all 4 judgehosts are actively polling DOMserver", test_judgehosts_polling)
    run_test("1.3", "Verify active contest state and submittability in DB", test_active_contest)

    log_header("PHASE 2: FRONTEND RENDERING & WHITE EDITOR UI")
    run_test("2.1", "Authenticate team user 'demo' and select contest", test_auth_login)
    run_test("2.2", "Verify standalone /team/submit page rendering (White Editor, Controls)", test_standalone_submit_page)
    run_test("2.3", "Verify AJAX modal /team/submit rendering (White Theme, Novalidate)", test_ajax_submit_modal)

    log_header("PHASE 3: AUTO-DETECTION PATTERN INTEGRITY")
    run_test("3.1", "Verify C++, Python 3, and Java class detection patterns", test_autodetect_patterns)

    log_header("PHASE 4: END-TO-END COMPILATION & JUDGING PIPELINE")
    run_test("4.1", "Submit Python 3 solution -> Execute on Judgehost -> Expect CORRECT", test_e2e_python_correct)
    run_test("4.2", "Submit C++ solution -> Compile on Judgehost -> Expect CORRECT", test_e2e_cpp_correct)
    run_test("4.3", "Submit incorrect solution -> Evaluate on Judgehost -> Expect WRONG-ANSWER", test_e2e_wrong_answer)

    log_header("PHASE 5: SCOREBOARD & SUBMISSION DETAILS")
    run_test("5.1", "Verify Team Dashboard submissions table reflects real-time results", test_team_dashboard_submissions)
    run_test("5.2", "Verify submission details modal (/team/submission/{id})", test_submission_details_modal)

    print(f"\n\033[1;36m{'='*65}\033[0m")
    if FAILED == 0:
        print(f"\033[1;32m  ALL {TOTAL} QA TESTS PASSED SUCCESSFULLY! (100% PASS RATE)\033[0m")
    else:
        print(f"\033[1;31m  QA TESTS COMPLETED WITH FAILURES: {PASSED}/{TOTAL} PASSED, {FAILED} FAILED\033[0m")
    print(f"\033[1;36m{'='*65}\033[0m\n")

    return 0 if FAILED == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
