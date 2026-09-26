# Windows conversation readiness and installer diagnostics

This fork starts from upstream v1.5.18 (`34335d27d54300eccb325cc652f6c93fef428b84`).
Its first development branch is `fix/windows-conversation-readiness`.

## Reported behavior

The skin can appear and the sidebar remains usable, but opening an existing conversation
can leave a spinner or blank content area. The report is from Store Codex 26.924.2738.0.
It is not evidence that all CDP connections fail on that version.

An upstream verification result illustrates a separate, confirmed bug:

```json
{
  "scope": { "baseState": "thread", "level": "L1", "missingL1": [] },
  "shell": { "visible": true },
  "sidebar": { "visible": true },
  "genericMain": { "visible": true },
  "composer": null,
  "genericInput": null,
  "readiness": { "structurePass": true },
  "pass": true
}
```

The old verifier accepts shell/sidebar geometry without evidence that the conversation
finished rendering. A successful CSS injection is not a successful conversation page.

## First repair scope

- Reject an empty thread shell even when the skin stylesheet and native sidebar are visible.
- Require visible native conversation content or a visible native composer input in the
  conversation surface. A search field or dialog editor must not satisfy this check.
- Preserve valid Home/settings verification and the existing fallback for Codex builds
  that cannot answer `Browser.getWindowForTarget`.
- Make silent Windows setup failures diagnosable without including raw configuration,
  conversation text, credentials, or private file contents in the failure record.
- Explain partial uninstall failures truthfully: restoration may already have happened
  even when runtime removal subsequently fails.

These changes fix verification and diagnosis. They do not establish the cause of the
reported conversation-loading failure, and they must not be advertised as a complete
fix for that symptom before live navigation tests pass.

Unknown utility routes currently inherit the renderer's `thread` classification. A
utility page without a native editor or conversation content can therefore fail this
strict check. Verify from Home or an actual conversation; utility-route classification
needs explicit native-route fixtures before this fork is released.

## Live acceptance before packaging

1. Start from a working official app with an existing conversation. Record only structural
   readiness signals; do not publish screenshots or logs containing private conversations.
2. Apply the bundled theme. Check the home screen and open the same conversation from the
   sidebar. Confirm actual messages, scrolling, and native input visibility.
3. If the route stalls, pause the skin in that same session and compare behavior. This
   separates decoration failure from managed-profile/app loading behavior.
4. Repeat with a downloaded theme, a narrow window, an open workspace panel, and an editor
   dialog. Dialog/sidebar inputs must not hide a broken conversation in verification.
5. Verify reload, theme switching, and full restoration. Then test a built installer on
   Windows, including forced install and uninstall failures.

The current development turn does not restart the active Codex session to run this matrix.
No new stable release or installer compatibility claim is made from fixture tests alone.

## Follow-up installer work

The engine replacement is atomic by itself, but the outer install also changes theme
storage and appearance configuration. A failure after runtime promotion can leave a
partially upgraded installation. A future install transaction must retain the old engine
until those later stages commit, and verify rollback using late-failure fixtures.
This requires separate design and tests; it is not silently folded into the diagnostics patch.

## Verification commands

```powershell
node --test windows/tests/*.test.mjs macos/tests/*.test.mjs tools/*.test.mjs
node tools/sync-runtime-assets.mjs --check
node windows/scripts/injector.mjs --check-payload
node macos/scripts/injector.mjs --check-payload
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File windows/tests/run-tests.ps1
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File windows/tests/installer-static.tests.ps1
```

Some macOS shell/native tests require macOS and must run in CI there. Keep test results,
local implementation, pushed commits, pull requests, and downloadable releases distinct.

## Development validation (2026-09-26)

- 52 Windows/tool and macOS renderer/thread Node tests passed on Windows.
- The empty-shell regression fails against unmodified upstream v1.5.18 and passes here.
- Windows PowerShell 5.1 and PowerShell 7 full runtime suites passed.
- Both PowerShell versions passed installer static checks and the focused failure
  tests, including a real silent bootstrap process returning its classified exit code.
- Shared-asset synchronization, selector provenance, and both payload checks passed.
- Full macOS native/shell testing and Inno Setup compilation require CI; no live
  conversation-navigation or installed-package signoff has been completed.

Fork CI is enabled for review. Automatic Release remains disabled until fork download
URLs, versioning, packaging and live acceptance have been reviewed.
