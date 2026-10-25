# Repository instructions

## Select local checks by the changed code and use arm64

- Local builds and tests only need the arm64 architecture. Build or test x86_64 and Universal binaries locally only when the user explicitly requests them.
- This arm64-only policy applies to local verification. Keep remote CI's existing Universal architecture coverage unless the user explicitly requests a CI change.
- For Swift, Xcode configuration, or macOS resource changes, start with `bash ci/check-macos.sh` and the affected arm64 Swift type check or build. Do not run Rust formatting, Clippy, or Rust tests when Rust code and its dependencies are unchanged.
- Run existing GUI cases when the changed behavior requires them and the user has authorized application automation. GUI tests must not synthesize keyboard input, use `typeText` or `typeKey`, switch the system input method, or open System Settings. Use menu actions and clipboard content for text editing; preserve and restore the clipboard unless the user has changed it during the test.
- For Rust changes, run Rust formatting, Clippy, and the relevant Rust tests. Expand to the full workspace when the change affects shared behavior.
- The existing GUI editing test must paste Chinese, English, and simple math into the application and automatically verify all three in its rendered preview, including after redo. Use menu actions without keyboard synthesis.
- Only an explicit request for the complete CI suite requires every check in `.github/workflows/tests.yml`. The complete local set is:

  ```sh
  cargo fmt --all -- --check
  cargo clippy --workspace --all-targets --locked -- -D warnings
  cargo test --workspace --locked
  bash ci/check-macos.sh
  bash ci/test-gui.sh --arm64
  ```

- `ci/test-gui.sh --arm64` must complete the arm64 application and test-runner build, verify the arm64 application architecture, and execute all XCUITest cases. Building alone does not count as running the GUI tests.
- Additional checks such as `bash ci/check-worker.sh` supplement the CI checks; they do not replace any CI task.
- Keep following the current workflow if CI changes. Report exactly which checks passed, failed, or could not run. Do not claim that all tests passed when any required check was skipped or blocked.
- Commit only after every requested check passes. Investigate and fix failures within the authorized scope, then rerun the affected checks. If an essential prerequisite is unavailable, state the concrete blocker and leave the changes uncommitted.

## Use `sb` to explore the code

- Use `sb` (the `ast-bro` toolkit) to read structure before opening full source files. Pull method bodies only after identifying the symbols needed.
- Stop at the step that answers the question:
  - `sb digest <dir>` for an unfamiliar directory.
  - `sb map <file>` for signatures and line ranges.
  - `sb show <file> <Symbol>` for a method, class, or Markdown section.
  - `sb implements <Type> <dir>` for subclasses and implementations.
  - `sb search "<query>"` when the file or symbol is unknown.
  - `sb find-related <file>:<line>` for similar code.
  - `sb surface <dir>` for the published public API.
  - `sb callers <Symbol> [<dir>]` and `sb callees <Symbol> [<dir>]` for call relationships.
  - `sb deps <file>`, `sb reverse-deps <file>`, `sb cycles [<dir>]`, and `sb graph [<dir>]` for import relationships.
- `deps` and `reverse-deps` take file paths; `graph` and `cycles` take directories. `callers` and `callees` take the symbol first.
- For `sb run` rewrites, run a dry run and inspect the diff before using `--write`.
- If parsing is unsupported or incomplete, read the necessary source directly.

## Execute established work immediately

- Once requirements or a defect's cause are clear, act immediately and continue until the authorized work is complete. Do not ask whether to start, continue, or implement an established fix.
- Existing authorization remains valid. Resolve routine implementation details independently.
- Ask only when essential information is missing or a higher-priority rule requires authorization that has not been granted. Continue unaffected work in the meantime.
- Treat reported defects, omissions, and mismatches as instructions to correct the existing work. Make the edit and run appropriate verification in the same turn.
- Before the final response, verify that the latest correction was implemented and checked. Do not substitute an acknowledgement or promise for executable work.
- When the user asks to correct instruction-following rules first, make that rules change first and preserve the original implementation task for continuation.

## Report file changes

- Every final response must list the files actually added, modified, or deleted during the session, briefly explain each change, and provide clickable absolute-path links.
- Report only your own changes from the current session. Do not attribute pre-existing changes or other tasks' changes to yourself.
- If no files were changed, explicitly state that no files were modified during the session.
