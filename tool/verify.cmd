@echo off
rem ============================================================================
rem KeepCon - one-command local verification before push (Windows cmd/PowerShell).
rem
rem Thin wrapper: locates Git Bash and runs tool/verify.sh.
rem Same reasoning as tool/verify_firestore_rules.cmd - the .sh drives a chain of
rem tools and assertions, and a batch port would be a second implementation that
rem drifts. One implementation, one behaviour.
rem
rem Why this wrapper exists at all: in cmd/PowerShell, `bash` resolves to WSL,
rem not Git Bash, so the documented `bash tool/verify.sh` fails on Windows -
rem and this script is the gate every push is supposed to pass.
rem
rem Usage (from anywhere in the repo):
rem   tool\verify.cmd
rem   set BASE=origin/main ^& tool\verify.cmd
rem
rem IMPORTANT - THIS FILE MUST STAY PURE ASCII, COMMENTS INCLUDED.
rem   See the note in tool/emulators.cmd for why.
rem ============================================================================
setlocal

cd /d "%~dp0.." || exit /b 1

call "%~dp0_find_git_bash.cmd" || exit /b 1

echo [KeepCon] Using Git Bash: %GIT_BASH%
"%GIT_BASH%" tool/verify.sh
exit /b %errorlevel%
