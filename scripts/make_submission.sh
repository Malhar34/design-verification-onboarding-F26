#!/usr/bin/env bash

# Build a reproducible DV onboarding submission archive. The script reruns the
# member and assigned encrypted-CPU suites, exports text coverage reports, and
# packages authored project files plus curated evidence. Large simulator state
# and staff-only answer material are deliberately excluded.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
SIM_DIR="$PROJECT_ROOT/sim/behav"
WORKSPACE="$SIM_DIR/WORKSPACE"

MEMBER_SEED=1
BUG_SEED=1
USER_ID=$(id -un)
MAX_ARCHIVE_MB=${MAX_SUBMISSION_MB:-100}
IMC_BIN=${IMC:-/tools/software/cadence/vmanageragl/25.09.020/tools.lnx86/vmgr/bin/imc}

log() {
    printf '[submission] %s\n' "$*"
}

die() {
    printf '[submission] ERROR: %s\n' "$*" >&2
    if [[ -n ${BUILD_DIR:-} && -d ${BUILD_DIR:-} ]]; then
        printf '[submission] Diagnostic files were retained in %s\n' "$BUILD_DIR" >&2
    fi
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

summary_value() {
    local label=$1
    local file=$2
    awk -v label="$label" '
        index($0, label) {
            value = $0
            sub(/^.*:[[:space:]]*/, "", value)
            sub(/[[:space:]].*$/, "", value)
        }
        END { if (value != "") print value }
    ' "$file"
}

require_zero_summary() {
    local label=$1
    local file=$2
    local value
    value=$(summary_value "$label" "$file")
    [[ $value =~ ^[0-9]+$ ]] || die "missing '$label' summary in $file"
    [[ $value -eq 0 ]] || die "$label is $value; inspect $file"
}

[[ $MAX_ARCHIVE_MB =~ ^[0-9]+$ && $MAX_ARCHIVE_MB -gt 0 ]] || \
    die "MAX_SUBMISSION_MB must be a positive integer"
[[ $USER_ID =~ ^[A-Za-z0-9._-]+$ ]] || \
    die "submission user contains unsupported filename characters: $USER_ID"

VARIANT=$(LC_ALL=C printf '%s' "$USER_ID" | od -An -tu1 | \
    awk '{ for (i = 1; i <= NF; i++) sum += $i } END { print sum % 3 }')

for command_name in make rsync zip unzip awk od git sha256sum; do
    require_command "$command_name"
done
require_command xrun
[[ -x $IMC_BIN ]] || die "IMC executable is unavailable: $IMC_BIN"

BUILD_DIR=$(mktemp -d "$PROJECT_ROOT/.submission-build.XXXXXX") || \
    die "could not create a submission build directory"
ARTIFACT_DIR="$BUILD_DIR/artifacts"
PACKAGE_DIR="$BUILD_DIR/package"
mkdir -p "$ARTIFACT_DIR" "$PACKAGE_DIR"

MEMBER_CONSOLE="$ARTIFACT_DIR/member_console.log"
BUG_CONSOLE="$ARTIFACT_DIR/bug_hunt_console.log"
MEMBER_LOG="$ARTIFACT_DIR/simulation.log"
BUG_LOG="$ARTIFACT_DIR/bug_hunt.log"
COVERAGE_SUMMARY="$ARTIFACT_DIR/coverage_summary.txt"
COVERAGE_UNCOVERED="$ARTIFACT_DIR/coverage_uncovered_code.txt"
COVERAGE_CONSOLE="$ARTIFACT_DIR/coverage_export_console.log"

log "running member suite with seed $MEMBER_SEED"
(
    cd "$SIM_DIR" || exit 1
    make clean
    make xrun SEED="$MEMBER_SEED"
) >"$MEMBER_CONSOLE" 2>&1
member_rc=$?

if [[ -f $WORKSPACE/simulation.log ]]; then
    cp "$WORKSPACE/simulation.log" "$MEMBER_LOG"
fi
if [[ $member_rc -ne 0 || ! -s $MEMBER_LOG ]]; then
    tail -n 80 "$MEMBER_CONSOLE" >&2
    die "member suite failed to run successfully"
fi
grep -q 'TEST PASSED' "$MEMBER_LOG" || die "member suite did not report TEST PASSED"
require_zero_summary 'Scoreboard mismatches' "$MEMBER_LOG"
require_zero_summary 'Driver timeouts' "$MEMBER_LOG"
require_zero_summary 'Monitor protocol errs' "$MEMBER_LOG"
require_zero_summary 'Assertion failures' "$MEMBER_LOG"

COV_RUN="$WORKSPACE/cov_work/scope/member"
[[ -d $COV_RUN ]] || die "member coverage database was not generated at $COV_RUN"

log "exporting member coverage reports"
imc_command="report -summary -text -metrics all -both -cumulative on -out {$COVERAGE_SUMMARY};"
imc_command+=" report -detail -text -metrics code -uncovered -source off -out {$COVERAGE_UNCOVERED}"
imc_args=(-64bit -load "$COV_RUN")
if [[ -f $SIM_DIR/exclusions.vRefine ]]; then
    imc_args+=(-load_refinement "$SIM_DIR/exclusions.vRefine")
fi
(
    cd "$BUILD_DIR" || exit 1
    "$IMC_BIN" "${imc_args[@]}" -execcmd "$imc_command"
) >"$COVERAGE_CONSOLE" 2>&1
coverage_rc=$?
[[ $coverage_rc -eq 0 && -s $COVERAGE_SUMMARY && -s $COVERAGE_UNCOVERED ]] || {
    tail -n 80 "$COVERAGE_CONSOLE" >&2
    die "coverage report export failed"
}

log "running encrypted bug-hunt variant $VARIANT with seed $BUG_SEED"
(
    cd "$SIM_DIR" || exit 1
    make bug_hunt \
        SEED="$BUG_SEED" \
        BUG_HUNT_USER="$USER_ID" \
        BUG_HUNT_VARIANT="$VARIANT"
) >"$BUG_CONSOLE" 2>&1
bug_rc=$?

if [[ -f $WORKSPACE/bug_hunt.log ]]; then
    cp "$WORKSPACE/bug_hunt.log" "$BUG_LOG"
fi
[[ -s $BUG_LOG ]] || {
    tail -n 80 "$BUG_CONSOLE" >&2
    die "bug-hunt suite did not produce bug_hunt.log"
}

# The fixed sanity seed may or may not expose the intentionally faulty CPU.
# Scoreboard mismatches are therefore allowed, while timeouts, protocol
# failures, assertions, missing summaries, and fatal simulator errors still
# invalidate the submission run.
bug_mismatches=$(summary_value 'Scoreboard mismatches' "$BUG_LOG")
[[ $bug_mismatches =~ ^[0-9]+$ ]] || die "bug-hunt run did not reach its final summary"
require_zero_summary 'Driver timeouts' "$BUG_LOG"
require_zero_summary 'Monitor protocol errs' "$BUG_LOG"
require_zero_summary 'Assertion failures' "$BUG_LOG"
if grep -Eq '\*F,|\$fatal|global timeout' "$BUG_LOG"; then
    die "bug-hunt run contains a fatal simulator or testbench failure"
fi
if [[ $bug_mismatches -eq 0 ]]; then
    [[ $bug_rc -eq 0 ]] || die "bug-hunt command failed without an intentional scoreboard mismatch"
    grep -q 'TEST PASSED' "$BUG_LOG" || die "bug-hunt sanity run did not report TEST PASSED"
fi

cat >"$ARTIFACT_DIR/test_summary.txt" <<EOF
Member suite seed: $MEMBER_SEED
Member suite result: PASS
Member command exit code: $member_rc

Bug-hunt user: $USER_ID
Bug-hunt variant: $VARIANT
Bug-hunt seed: $BUG_SEED
Bug-hunt scoreboard mismatches: $bug_mismatches
Bug-hunt command exit code: $bug_rc (nonzero is allowed only for intentional scoreboard mismatches)
Bug-hunt infrastructure result: COMPLETE
EOF

if [[ $bug_mismatches -eq 0 ]]; then
    cat >>"$ARTIFACT_DIR/test_summary.txt" <<EOF
Bug-hunt sanity note: the deterministic packaging run did not trigger the injected bug.
EOF
fi

branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || true)
commit=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || true)
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
cat >"$ARTIFACT_DIR/submission_manifest.txt" <<EOF
DV onboarding submission
Generated UTC: $timestamp
User: $USER_ID
Branch: ${branch:-unknown}
Commit: ${commit:-unknown}
Member seed: $MEMBER_SEED
Bug-hunt seed: $BUG_SEED
Bug-hunt variant: $VARIANT

Large generated state is intentionally omitted:
- sim/behav/WORKSPACE except the curated logs and coverage reports
- waveform databases (*.shm)
- Xcelium snapshots and raw coverage databases
- Git metadata, previous submission ZIPs, and staff-only answers

Any screenshots and authored evidence elsewhere in the project are included.
EOF

git -C "$PROJECT_ROOT" status --short >"$ARTIFACT_DIR/git_status.txt" 2>&1 || true
git -C "$PROJECT_ROOT" diff --no-ext-diff >"$ARTIFACT_DIR/working_tree.patch" 2>&1 || true
git -C "$PROJECT_ROOT" diff --cached --no-ext-diff >"$ARTIFACT_DIR/staged_changes.patch" 2>&1 || true

: >"$ARTIFACT_DIR/submission_warnings.txt"
for required_file in testplan_initial.md testplan_final.md; do
    if [[ ! -s $PROJECT_ROOT/$required_file ]]; then
        printf 'Missing or empty deliverable: %s\n' "$required_file" \
            >>"$ARTIFACT_DIR/submission_warnings.txt"
    fi
done
printf '%s\n' \
    'Confirm that your bug report, minimized reproducer, and waveform/coverage screenshots are saved in the project.' \
    >>"$ARTIFACT_DIR/submission_warnings.txt"

log "assembling project archive"
rsync -a \
    --exclude '/.git' \
    --exclude '/staff' \
    --exclude '/tb_old_golden' \
    --exclude '/sim/behav/WORKSPACE' \
    --exclude '/imc.key' \
    --exclude '/imc.log' \
    --exclude '/mdv.log' \
    --exclude '/.submission-build.*' \
    --exclude '/*_submission.zip' \
    "$PROJECT_ROOT/" "$PACKAGE_DIR/"

mkdir -p "$PACKAGE_DIR/submission_artifacts"
cp -a "$ARTIFACT_DIR/." "$PACKAGE_DIR/submission_artifacts/"
(
    cd "$PACKAGE_DIR" || exit 1
    find . -type f -print | LC_ALL=C sort \
        >submission_artifacts/archive_file_list.txt
)

ARCHIVE_NAME="${USER_ID}_submission.zip"
ARCHIVE_TEMP="$BUILD_DIR/$ARCHIVE_NAME"
(
    cd "$PACKAGE_DIR" || exit 1
    zip -q -r "$ARCHIVE_TEMP" .
)
zip_rc=$?
[[ $zip_rc -eq 0 && -s $ARCHIVE_TEMP ]] || die "ZIP creation failed"
unzip -tq "$ARCHIVE_TEMP" >/dev/null || die "ZIP integrity check failed"

if unzip -Z1 "$ARCHIVE_TEMP" | grep -Eq '(^|/)staff/|(^|/)WORKSPACE/|\.shm(/|$)'; then
    die "archive unexpectedly contains staff material or a large simulator database"
fi

archive_bytes=$(stat -c '%s' "$ARCHIVE_TEMP")
max_bytes=$((MAX_ARCHIVE_MB * 1024 * 1024))
[[ $archive_bytes -le $max_bytes ]] || \
    die "archive is larger than ${MAX_ARCHIVE_MB} MiB; inspect authored files for oversized artifacts"

mv -f "$ARCHIVE_TEMP" "$PROJECT_ROOT/$ARCHIVE_NAME"
archive_hash=$(sha256sum "$PROJECT_ROOT/$ARCHIVE_NAME" | awk '{print $1}')
archive_size=$(du -h "$PROJECT_ROOT/$ARCHIVE_NAME" | awk '{print $1}')

find "$BUILD_DIR" -depth -delete

log "created $PROJECT_ROOT/$ARCHIVE_NAME"
log "size: $archive_size"
log "sha256: $archive_hash"
