#!/usr/bin/env bash
#
# exp-update-tester.sh - Test suite for exp-update
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR=""
ORIGINAL_DIR="$PWD"
SANDBOX_HOME=""

# Every test runs against a home directory of its own. Some of what follows sources
# the update script in a way that lets its main body run, and that body reaches for
# $HOME -- so run against a real one it marked everything in ~/.local/bin
# executable and removed a directory from ~/.config.
setup_sandbox_home() {
  SANDBOX_HOME=$(mktemp -d -t dotfiles-test-home.XXXXXX)
  mkdir -p "$SANDBOX_HOME/.config" "$SANDBOX_HOME/.cache" \
           "$SANDBOX_HOME/.local/bin" "$SANDBOX_HOME/.local/share" "$SANDBOX_HOME/.local/state"
  export HOME="$SANDBOX_HOME"
  export XDG_CONFIG_HOME="$SANDBOX_HOME/.config"
  export XDG_DATA_HOME="$SANDBOX_HOME/.local/share"
  export XDG_CACHE_HOME="$SANDBOX_HOME/.cache"
  export XDG_STATE_HOME="$SANDBOX_HOME/.local/state"
  export XDG_BIN_HOME="$SANDBOX_HOME/.local/bin"
}

# A repository the update can actually be run inside. Copying sdata as it stands
# drags the package build trees along, which come to gigabytes.
make_runnable_repo() {
  local dest="$1"
  mkdir -p "$dest"
  cp "$ORIGINAL_DIR/setup" "$dest/"
  rsync -a --exclude 'src/' --exclude 'pkg/' --exclude '*.pkg.tar.*' "$ORIGINAL_DIR/sdata" "$dest/"
  cp -r "$ORIGINAL_DIR/dots" "$dest/"
  chmod +x "$dest/setup"
}

# Run the update inside the current directory, capturing everything it printed.
run_update() {
  local output_file="$1"; shift
  ./setup exp-update --skip-notice --non-interactive "$@" > "$output_file" 2>&1 || true
}

# Helper functions
log_test() {
  echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  ((TESTS_FAILED++))
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Setup test environment
setup_test_env() {
  local temp_dir
  temp_dir=$(mktemp -d -t dotfiles-test.XXXXXX)

  cd "$temp_dir" || { echo "Failed to cd to test directory"; return 1; }
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  git commit --allow-empty -m "Initial commit" -q

  echo "$temp_dir"
}

# Cleanup test environment
cleanup_test_env() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
    TEST_DIR=""
  fi
}

# A repository holding one configuration file, ready to be updated from.
prepare_update_repo() {
  local test_repo
  test_repo=$(mktemp -d -t dotfiles-test.XXXXXX)
  make_runnable_repo "$test_repo"
  git -C "$test_repo" init -q
  git -C "$test_repo" config user.email "test@example.com"
  git -C "$test_repo" config user.name "Test User"
  mkdir -p "$test_repo/dots/.config/test-app"
  echo "from the repository" > "$test_repo/dots/.config/test-app/config.conf"
  git -C "$test_repo" add . >/dev/null 2>&1
  git -C "$test_repo" commit -m "Add test config" -q
  printf '%s' "$test_repo"
}

# Test 2: Script has no syntax errors
test_syntax() {
  log_test "Checking script syntax"

  if bash -n setup; then
    log_pass "No syntax errors found"
    return 0
  else
    log_fail "Syntax errors detected"
    return 1
  fi
}

# Test 3: Help option works
test_help_option() {
  log_test "Testing --help option"

  if ./setup exp-update --help 2>&1 | grep -qiE "(Syntax|Options|exp-update)"; then
    log_pass "Help option works"
    return 0
  else
    log_fail "Help option failed"
    return 1
  fi
}

# Test 4: Test repository structure detection (dots/ prefix)
test_dots_structure() {
  log_test "Testing dots/ prefix structure detection"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p dots/.config/test-app
  mkdir -p dots/.local/bin
  echo "test config" > dots/.config/test-app/config.conf

  git add .
  git commit -m "Add dots structure" -q

  cat > test_detection.sh << EOF
#!/bin/bash
# Mock logging and style functions/variables
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1"; exit 1; }
STY_CYAN="" STY_RST="" STY_YELLOW=""

# Set required environment variables for exp-update/0.run.sh
SKIP_NOTICE=true
REPO_ROOT="\$1"
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh"
detected_dirs=\$(detect_repo_structure)
if [[ -n "\$detected_dirs" ]]; then
  read -ra MONITOR_DIRS <<<"\$detected_dirs"
fi
echo "Structure: \${MONITOR_DIRS[*]}"
EOF

  chmod +x test_detection.sh
  result=$(./test_detection.sh "$test_repo")

  if [[ "$result" == *"dots/.config"* ]]; then
    log_pass "Dots structure detected correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Failed to detect dots structure. Got: $result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 5: Test flat structure detection
test_flat_structure() {
  log_test "Testing flat structure detection"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p .config/test-app
  mkdir -p .local/bin
  echo "test config" > .config/test-app/config.conf

  git add .
  git commit -m "Add flat structure" -q

  cat > test_detection.sh << EOF
#!/bin/bash
# Mock logging and style functions/variables
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1"; exit 1; }

# Set required environment variables for exp-update
SKIP_NOTICE=true
REPO_ROOT="\$1"
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh"
detected_dirs=\$(detect_repo_structure)
if [[ -n "\$detected_dirs" ]]; then
  read -ra MONITOR_DIRS <<<"\$detected_dirs"
fi
echo "Structure: \${MONITOR_DIRS[*]}"
EOF

  chmod +x test_detection.sh
  result=$(./test_detection.sh "$test_repo")

  if [[ "$result" == *".config"* ]] && [[ "$result" != *"dots/"* ]]; then
    log_pass "Flat structure detected correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Failed to detect flat structure. Got: $result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 6: entries under dots/ arrive under the home directory
test_dots_mapping() {
  log_test "Testing that dots/ entries are written under the home directory"

  local test_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  rm -rf "${HOME}/.config/test-app"
  run_update update_output.txt --force

  if [[ -f "${HOME}/.config/test-app/config.conf" ]]; then
    log_pass "dots/.config/test-app/config.conf arrived under ${HOME}/.config"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "The file never arrived under the home directory"
    tail -n 20 update_output.txt
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 7: Test ignore file patterns - FIXED
test_ignore_patterns() {
  log_test "Testing ignore file pattern matching"
  
  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"
  
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  
  cat > .updateignore << 'EOF'
*.log
secrets/
.config/private*
*backup*
EOF
  
  mkdir -p .config
  mkdir -p secrets
  
  cat > test_ignore.sh << EOF
#!/bin/bash
# Suppress all output from sourced script
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

# FIXED: Set REPO_ROOT before sourcing exp-update
REPO_ROOT="\$1"
export REPO_ROOT

# Set other required environment variables
SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true

UPDATE_IGNORE_FILE="\${REPO_ROOT}/.updateignore"
HOME_UPDATE_IGNORE_FILE="/dev/null"

# Only the definitions are wanted here, not a whole update run
SOURCE_ONLY=true

# Source the production script to use the real should_ignore function
# Redirect all unwanted output to stderr, then to /dev/null
source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh" 2>/dev/null

# The main body used to do this on the way past; it no longer runs here
load_ignore_patterns

test_cases=(
  "\$REPO_ROOT/app.log:0"
  "\$REPO_ROOT/secrets/key.txt:0" 
  "\$REPO_ROOT/.config/private-config:0"
  "\$REPO_ROOT/.config/backup-file:0"
  "\$REPO_ROOT/normal-config:1"
)

all_passed=true
for test_case in "\${test_cases[@]}"; do
  IFS=":" read -r file expected <<< "\$test_case"
  mkdir -p "\$(dirname "\$file")"
  touch "\$file"
  
  if should_ignore "\$file"; then
    result=0
  else
    result=1
  fi
  
  if [[ \$result -ne \$expected ]]; then
    echo "FAIL: \$file (expected: \$expected, got: \$result)"
    all_passed=false
  fi
done

if [[ "\$all_passed" == true ]]; then
  echo "PASS"
else
  echo "FAIL"
fi
EOF
  
  chmod +x test_ignore.sh
  result=$(./test_ignore.sh "$test_repo" 2>&1 | grep -E "^(PASS|FAIL)")
  
  if [[ "$result" == "PASS" ]]; then
    log_pass "All ignore pattern tests passed"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Some ignore pattern tests failed"
    echo "$result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 8: Test safe_read security - FIXED
test_safe_read_security() {
  log_test "Testing safe_read uses secure assignment (printf -v)"

  local safe_read_function
  safe_read_function=$(awk '/^safe_read\(\) \{/,/^\}/' "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh")

  if [[ -z "$safe_read_function" ]]; then
    log_fail "Could not find safe_read function"
    return 1
  fi

  # FIXED: Remove comments before checking for eval
  # The function has a comment mentioning eval, which shouldn't count
  local function_without_comments
  function_without_comments=$(echo "$safe_read_function" | sed 's/#.*$//')
  
  local has_printf_v=false
  local has_eval=false
  
  if echo "$safe_read_function" | grep -F 'printf -v' > /dev/null; then
    has_printf_v=true
  fi
  
  # Check for eval in actual code (not comments)
  if echo "$function_without_comments" | grep -w 'eval' > /dev/null; then
    has_eval=true
  fi

  if [[ "$has_printf_v" == true ]] && [[ "$has_eval" == false ]]; then
    log_pass "safe_read uses secure printf -v assignment and no eval"
    return 0
  else
    log_fail "safe_read does not use secure assignment or contains eval (has_printf_v=$has_printf_v, has_eval=$has_eval)"
    echo "Function content:"
    echo "$safe_read_function"
    return 1
  fi
}

# Test 9: dry-run writes nothing
test_dry_run() {
  log_test "Testing dry-run mode"

  local test_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  rm -rf "${HOME}/.config/test-app"
  # Forced, or nothing would be compared at all and the run would write nothing
  # whatever dry-run did.
  run_update dry_run_output.txt --dry-run --force

  local ok=true
  if ! grep -q "DRY-RUN" dry_run_output.txt; then
    log_fail "Dry-run mode not indicated in the output"
    ok=false
  fi
  if [[ -e "${HOME}/.config/test-app/config.conf" ]]; then
    log_fail "Dry-run created a file in the home directory"
    ok=false
  fi

  if [[ "$ok" == true ]]; then
    log_pass "Dry-run reported itself and wrote nothing"
    cd "$ORIGINAL_DIR"
    return 0
  fi
  tail -n 20 dry_run_output.txt
  cd "$ORIGINAL_DIR"
  return 1
}

# Test 10: Test command-line flags
test_flags() {
  log_test "Testing command-line flags"

  # Only test non-interactive flags
  local flags=("-h" "--help")
  local all_passed=true

  for flag in "${flags[@]}"; do
    if ./setup exp-update "$flag" 2>&1 | grep -qiE "(Syntax|Options|exp-update)"; then
      log_test "  ✓ $flag recognized"
    else
      log_test "  ✗ $flag not recognized"
      all_passed=false
    fi
  done

  if [[ "$all_passed" == true ]]; then
    log_pass "Help flags recognized correctly"
    return 0
  else
    log_fail "Some flags not recognized properly"
    return 1
  fi
}

# Test 11: Check for shellcheck
test_shellcheck() {
  log_test "Running shellcheck (if available)"
  
  if ! command -v shellcheck &>/dev/null; then
    log_test "shellcheck not found, skipping static analysis"
    return 0
  fi
  
  if shellcheck -e SC1090,SC1091,SC2148,SC2034,SC2155,SC2164 setup; then
    log_pass "shellcheck passed"
    return 0
  else
    log_fail "shellcheck found issues"
    return 1
  fi
}

# Test 12: Test lock file mechanism
test_lock_file() {
  log_test "Testing lock file mechanism"
  
  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"
  
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  
  make_runnable_repo "$test_repo"
  
  git add .
  git commit -m "Add files" -q
  
  # Create a fake lock file
  echo "99999" > .update-lock
  
  # Try to run update - should fail due to lock
  if ./setup exp-update --skip-notice --non-interactive > lock_test_output.txt 2>&1; then
    if grep -q "stale lock" lock_test_output.txt; then
      log_pass "Lock file mechanism works (detected stale lock)"
      cd "$ORIGINAL_DIR"
      return 0
    fi
  fi
  log_fail "Lock file mechanism did not work as expected"
  cat lock_test_output.txt  # Show output for debugging
  cd "$ORIGINAL_DIR"
  return 1
}

# Test 13: Test ** substring ignore patterns - FIXED
test_substring_ignore_patterns() {
  log_test "Testing ** substring ignore pattern matching"

  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  cat > .updateignore << 'EOF'
**temp**
**backup**
**testfile**
EOF

  mkdir -p .config/test-app
  mkdir -p temp-backup-dir
  mkdir -p .local/share/test-temp
  mkdir -p .config/temp-file

  cat > test_substring_ignore.sh << EOF
#!/bin/bash
# Suppress all output from sourced script
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

# FIXED: Set REPO_ROOT before sourcing exp-update
REPO_ROOT="\$1"
export REPO_ROOT

# Set other required environment variables
SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true

UPDATE_IGNORE_FILE="\${REPO_ROOT}/.updateignore"
HOME_UPDATE_IGNORE_FILE="/dev/null"

# Only the definitions are wanted here, not a whole update run
SOURCE_ONLY=true

# Source the production script to use the real should_ignore function
source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh" 2>/dev/null

# Load patterns into cache
load_ignore_patterns

test_cases=(
  "\$REPO_ROOT/temp-backup-dir/file:0"
  "\$REPO_ROOT/.config/test-app/temp.conf:0"
  "\$REPO_ROOT/.local/share/test-temp/data:0"
  "\$REPO_ROOT/.config/temp-file/config:0"
  "\$REPO_ROOT/normal-config:1"
  "\$REPO_ROOT/.config/my-testfile.conf:0"
)

all_passed=true
for test_case in "\${test_cases[@]}"; do
  IFS=":" read -r file expected <<< "\$test_case"
  mkdir -p "\$(dirname "\$file")"
  touch "\$file"

  if should_ignore "\$file"; then
    result=0
  else
    result=1
  fi

  if [[ \$result -ne \$expected ]]; then
    echo "FAIL: \$file (expected: \$expected, got: \$result)"
    all_passed=false
  fi
done

if [[ "\$all_passed" == true ]]; then
  echo "PASS"
else
  echo "FAIL"
fi
EOF

  chmod +x test_substring_ignore.sh
  result=$(./test_substring_ignore.sh "$test_repo" 2>&1 | grep -E "^(PASS|FAIL)")

  if [[ "$result" == "PASS" ]]; then
    log_pass "** substring ignore patterns work correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "** substring ignore patterns failed"
    echo "$result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 14: Test ensure_directory caching
test_directory_caching() {
  log_test "Testing directory creation caching"
  
  local test_repo
  test_repo=$(setup_test_env)
  TEST_DIR="$test_repo"
  
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  
  cat > test_dir_cache.sh << EOF
#!/bin/bash
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

REPO_ROOT="\$1"
export REPO_ROOT

SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh" 2>/dev/null

test_dir="/tmp/test-ensure-dir-\$\$"

# First call should create
ensure_directory "\$test_dir"
result1=\$?

# Second call should use cache
ensure_directory "\$test_dir"
result2=\$?

# Check if CREATED_DIRS has the entry
if [[ -n "\${CREATED_DIRS[\$test_dir]:-}" ]] && [[ \$result1 -eq 0 ]] && [[ \$result2 -eq 0 ]]; then
  echo "PASS"
  rm -rf "\$test_dir"
else
  echo "FAIL"
fi
EOF
  
  chmod +x test_dir_cache.sh
  result=$(./test_dir_cache.sh "$test_repo" 2>&1 | grep -E "^(PASS|FAIL)")
  
  if [[ "$result" == "PASS" ]]; then
    log_pass "Directory creation caching works"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Directory creation caching failed"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 15: the real safe_read in non-interactive mode
test_safe_read_noninteractive() {
  log_test "Testing safe_read in non-interactive mode"

  local test_repo
  test_repo=$(mktemp -d -t dotfiles-test.XXXXXX)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  # Unquoted, so the path to the repository is filled in. Quoted, the two source
  # lines below reached for /sdata/... and failed without anyone noticing, and the
  # function under test was a simplified copy written out right here rather than
  # the one that ships.
  cat > test_safe_read.sh << EOF
#!/bin/bash
source "$ORIGINAL_DIR/sdata/lib/environment-variables.sh"
source "$ORIGINAL_DIR/sdata/lib/functions.sh"
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }
log_die() { echo "ERROR: \$1" >&2; exit 1; }

REPO_ROOT="$ORIGINAL_DIR"
SKIP_NOTICE=true
CHECK_PACKAGES=false
DRY_RUN=false
FORCE_CHECK=false
VERBOSE=false
NON_INTERACTIVE=true
SOURCE_ONLY=true

source "$ORIGINAL_DIR/sdata/subcmd-exp-update/0.run.sh"

# With a default, non-interactive mode takes it
if safe_read "Test: " answer "default_value" && [[ "\$answer" == "default_value" ]]; then
  echo "TEST1: PASS"
else
  echo "TEST1: FAIL - got '\${answer:-}'"
fi

# Without one, there is nothing it may assume
if safe_read "Test: " answer ""; then
  echo "TEST2: FAIL - should have refused"
else
  echo "TEST2: PASS - correctly refused"
fi
EOF

  chmod +x test_safe_read.sh
  local result
  result=$(./test_safe_read.sh 2>&1)

  if grep -q "TEST1: PASS" <<<"$result" && grep -q "TEST2: PASS" <<<"$result"; then
    log_pass "safe_read handles non-interactive mode correctly"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "safe_read non-interactive mode failed"
    echo "$result"
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 16: a conflict resolved as "replace" overwrites what was there
test_conflict_replace() {
  log_test "Testing conflict resolution: replace"

  local test_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p "${HOME}/.config/test-app"
  echo "mine, from before" > "${HOME}/.config/test-app/config.conf"

  run_update out.txt --force --default-choice replace

  if [[ "$(cat "${HOME}/.config/test-app/config.conf")" == "from the repository" ]]; then
    log_pass "The repository version replaced the local one"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "The local file was not replaced"
    tail -n 20 out.txt
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 17: a conflict resolved as "keep" leaves the local file alone
test_conflict_keep() {
  log_test "Testing conflict resolution: keep"

  local test_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p "${HOME}/.config/test-app"
  echo "mine, from before" > "${HOME}/.config/test-app/config.conf"

  run_update out.txt --force --default-choice keep

  if [[ "$(cat "${HOME}/.config/test-app/config.conf")" == "mine, from before" ]]; then
    log_pass "The local version was kept"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "The local file was overwritten despite choosing to keep it"
    tail -n 20 out.txt
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 18: "backup" both saves the local file and replaces it
test_conflict_backup() {
  log_test "Testing conflict resolution: backup then replace"

  local test_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  mkdir -p "${HOME}/.config/test-app"
  echo "mine, from before" > "${HOME}/.config/test-app/config.conf"

  run_update out.txt --force --default-choice backup

  local saved
  saved=$(grep -rl "mine, from before" .update-backups 2>/dev/null | head -1)

  if [[ -n "$saved" ]] && [[ "$(cat "${HOME}/.config/test-app/config.conf")" == "from the repository" ]]; then
    log_pass "The local file was saved and then replaced"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "Backup missing or the file was not replaced (saved: ${saved:-none})"
    tail -n 20 out.txt
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 19: a lock held by a live process is left where it is
test_lock_not_released_by_others() {
  log_test "Testing that a refused run leaves the lock alone"

  local test_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }

  sleep 60 &
  local holder=$!
  echo "$holder" > .update-lock

  run_update lock_out.txt --force

  local refused=false still_there=false
  grep -q "Another update is already running" lock_out.txt && refused=true
  [[ -f .update-lock ]] && still_there=true

  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  rm -f .update-lock

  if [[ "$refused" == true ]] && [[ "$still_there" == true ]]; then
    log_pass "The run refused to start and the lock survived"
    cd "$ORIGINAL_DIR"
    return 0
  else
    log_fail "refused=$refused, lock still present=$still_there"
    tail -n 20 lock_out.txt
    cd "$ORIGINAL_DIR"
    return 1
  fi
}

# Test 20: a second run with nothing new does not offer the previous run's files
test_diff_base_from_run_start() {
  log_test "Testing that the comparison starts from this run's own commit"

  local test_repo origin_repo
  test_repo=$(prepare_update_repo)
  TEST_DIR="$test_repo"
  origin_repo=$(mktemp -d -t dotfiles-origin.XXXXXX)
  git -C "$origin_repo" init -q --bare

  cd "$test_repo" || { log_fail "Failed to cd to test directory"; return 1; }
  git branch -M main
  git remote add origin "$origin_repo"
  git push -q -u origin main

  # Something new upstream, so the first run has real work to do. The branch is
  # named explicitly: a bare repository points its HEAD at master, so cloning
  # without it checks nothing out and the change below is never made -- which let
  # this test pass while proving nothing at all.
  local other_clone
  other_clone=$(mktemp -d -t dotfiles-other.XXXXXX)
  git clone -q -b main "$origin_repo" "$other_clone"
  git -C "$other_clone" config user.email "test@example.com"
  git -C "$other_clone" config user.name "Test User"
  echo "changed upstream" > "$other_clone/dots/.config/test-app/config.conf"
  git -C "$other_clone" commit -qam "upstream change"
  git -C "$other_clone" push -q origin main

  # Refuse to go on unless the setup really produced something to pull
  if [[ "$(git -C "$other_clone" rev-list --count main)" -lt 2 ]]; then
    log_fail "Test setup failed: no upstream commit was created"
    rm -rf "$origin_repo" "$other_clone"
    cd "$ORIGINAL_DIR"
    return 1
  fi

  run_update first_run.txt --default-choice replace
  if ! grep -qE "Successfully pulled|New commits detected" first_run.txt; then
    log_fail "Test setup failed: the first run pulled nothing"
    tail -n 10 first_run.txt
    rm -rf "$origin_repo" "$other_clone"
    cd "$ORIGINAL_DIR"
    return 1
  fi

  run_update second_run.txt --default-choice replace

  local verdict=0
  if grep -q "No new commits found" second_run.txt; then
    log_pass "The second run saw nothing to do, as it should"
  else
    log_fail "The second run went looking through the previous run's changes again"
    grep -iE "new commits|skipping file updates" second_run.txt | head -n 4
    verdict=1
  fi

  rm -rf "$origin_repo" "$other_clone"
  cd "$ORIGINAL_DIR"
  return $verdict
}

# Main test runner
main() {
  echo -e "${BLUE}================================${NC}"
  echo -e "${BLUE}  Update.sh Test Suite (Enhanced)${NC}"
  echo -e "${BLUE}================================${NC}\n"

  if [[ ! -f "setup" ]]; then
    log_error "Please run this test from the directory containing setup"
    exit 1
  fi

  chmod +x setup 2>/dev/null || true

  setup_sandbox_home
  echo -e "${BLUE}Running against a sandbox home: ${SANDBOX_HOME}${NC}\n"

  # Define tests
  tests=(
    "test_syntax"
    "test_help_option"
    "test_dots_structure"
    "test_flat_structure"
    "test_dots_mapping"
    "test_ignore_patterns"
    "test_substring_ignore_patterns"
    "test_safe_read_security"
    "test_dry_run"
    "test_flags"
    "test_shellcheck"
    "test_lock_file"
    "test_directory_caching"
    "test_safe_read_noninteractive"
    "test_conflict_replace"
    "test_conflict_keep"
    "test_conflict_backup"
    "test_lock_not_released_by_others"
    "test_diff_base_from_run_start"
  )

  # Run tests
  for test in "${tests[@]}"; do
    # Each test builds a repository of its own; without this they all sat around
    # until the end of the run, which is a great deal of disk for no reason.
    cleanup_test_env
    if $test; then
      echo "✓ $test passed"
    else
      echo "✗ $test failed"
    fi
    echo
  done

  # Summary
  echo -e "${BLUE}================================${NC}"
  echo -e "${BLUE}  Test Summary${NC}"
  echo -e "${BLUE}================================${NC}"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  echo -e "${BLUE}Total:  ${#tests[@]}${NC}\n"

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed.${NC}\n"
    exit 0
  else
    echo -e "${RED}Some tests failed.${NC}\n"
    exit 1
  fi
}

# Global cleanup
cleanup() {
  echo "Cleaning up test files..."
  cleanup_test_env
  rm -f test_detection.sh test_ignore.sh test_safe_read.sh test_fresh_clone.sh test_substring_ignore.sh dry_run_output.txt 2>/dev/null || true
  rm -f test_caching.sh test_dir_cache.sh 2>/dev/null || true
  rm -f lock_test_output.txt out.txt first_run.txt second_run.txt update_output.txt 2>/dev/null || true
  if [[ -n "${SANDBOX_HOME:-}" && -d "$SANDBOX_HOME" ]]; then
    rm -rf "$SANDBOX_HOME"
    SANDBOX_HOME=""
  fi
}

trap cleanup EXIT INT TERM

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
