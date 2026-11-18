# ONNX Runtime supply-chain verification

Assessment date: November 17, 2026 (America/Toronto).

## Conclusion and scope

The vendored payloads have verified Microsoft/NuGet provenance and predate the
reported November 17 `agent-framework` PyPI compromise. Every distributed payload
file matches the signature-verified source package byte-for-byte. No evidence of
exposure to that specific malicious package was found in the project checks below.
These checks support using the verified official 1.30.0 payloads for this outage
workaround. They do not constitute a guarantee that native code has no malware,
vulnerabilities, or previously undiscovered upstream compromise.

This assessment covers the Godot dependency packages in this PR, tracked project
dependency declarations on fetched branches, the recovery-source CI run, and
available runs during the reported attack window. It is not an organization-wide
incident-response audit or a forensic examination of contributors' machines.

## Cryptographic source evidence

Source: `Microsoft.ML.OnnxRuntime` 1.30.0 from the official NuGet flat-container URL
pinned in `Godot/dependencies.lock.json`.

- Source archive SHA-256: `30df119bd9164eaa187666d93147448fdd4a9a1a3caf83f1505daf7af2d1c5d2`.
- Source revision in the signed nuspec: `f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7`.
- `nuget verify -All` (NuGet 6.14.0.116) exited 0: **Successfully verified package**.
- Author: Microsoft Corporation; author certificate SHA-256:
  `566A31882BE208BE4422F7CFD66ED09F5D4524A5994F50CCC8B05EC0528C1353`.
- Author signature timestamp: September 10, 2026, 08:09:37 UTC
  (04:09:37 America/Toronto).
- Repository: NuGet.org; repository certificate SHA-256:
  `1F4B311D9ACC115C8DC8018B5A49E00FCE6DA8E2855F9F014CA6F34570BC482D`.
- Repository signature timestamp: September 10, 2026, 15:39:30 UTC
  (11:39:30 America/Toronto).
- The NuGet CLI executable itself had a valid Microsoft Authenticode signature
  before it was executed. The saved original Windows ONNX DLL also had a valid
  Microsoft Authenticode signature.

The complete verification output is in
[`nuget-signature-verification.txt`](nuget-signature-verification.txt).
Certificate expiration does not by itself invalidate a trusted timestamped
signature; NuGet validated the signature and timestamp chains successfully.

`verify_onnxruntime_source.py` verified all 75 packaged file entries across the
three hosts: 69 payload entries match their signed NuGet members byte-for-byte,
and six generated metadata entries match the pinned version/revision. The same
headers are present on multiple platforms, and Unix aliases duplicate a payload;
these counts do not represent 75 distinct upstream files.

## Recovery cross-check

The initial emergency investigation found saved Windows files and Linux/macOS
libraries in project CI run
[44039915487](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/44039915487),
which completed at November 17, 07:40:48 UTC, before the reported malicious PyPI
uploads beginning at 20:35 UTC.

The saved Windows runtime and import libraries and recovered Linux runtime match
the signed NuGet payload hashes. The recovered exported macOS library differs
only inside its Mach-O `LC_CODE_SIGNATURE` region: both signature regions begin
at byte 43,506,352 and occupy 373,072 bytes. SHA-256 of all bytes outside that
region is `afc1140c8e0ae59c57c7cb078285638bdb438c367c198b9add3c316f470e4d2c`
for both copies. Export re-signing is consistent with this difference.

The final packages are repacked directly from verified NuGet bytes, including the
original macOS signature, rather than relying on the recovered copies. Recovery
artifacts are not an independent trust anchor for the final packages.

## Reported compromise exposure checks

The [reported incident](https://www.endorlabs.com/learn/agent-framework-compromised-software-supply-chain-attack)
affects PyPI `agent-framework` 1.26.1 and 1.26.2, with Python startup-hook payloads
named `agent_framework_meta` and `af_runtime_diag`. The HN comment linking the
ONNX outage to this incident is speculation. No authoritative connection was
established; direct access to the upstream GitHub repositories remained unavailable.

- No affected-package/payload references were found in tracked dependency,
  workflow, configuration, or Python files across the eight locally fetched
  `origin` refs checked, including `main` and the PR #51 feature branch.
- No matching package/payload filenames were found in the shared CSC301 workspace
  or the checked Python 3.12 system/user site-packages locations. This is an
  indicator check, not a complete host-forensics verdict.
- Full available logs of source run 44039915487 and incident-window run
  [44233340192](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/44233340192)
  contain no affected package or payload names. Source-run package installation
  records were inspected; the listed dependencies do not include `agent-framework`.
- At the time of the run-list check, the only project runs returned since
  November 17, 20:35 UTC were failed run 44233340192 and this PR's running validation
  run 44240193133. Final validation logs are checked separately before readiness.

Absence from declarations/logs does not prove absence from an unlogged environment
or another developer machine. No credentials were rotated or caches deleted on
speculation. If actual affected-package execution is discovered, preserve logs,
isolate the environment, rotate exposed credentials from a clean system, and
rebuild from verified sources.

## Advisory and malware checks

OSV querybatch was queried for the exact packages `Microsoft.ML.OnnxRuntime`
(NuGet) 1.30.0 and `onnxruntime` (PyPI) 1.30.0. Both returned empty vulnerability
results. This is an advisory-database check, not a guarantee against undisclosed
vulnerabilities or malicious code. The exact queries/results are preserved in
[`advisory-check.json`](advisory-check.json).

Microsoft Defender scanned the vendored package directory with automatic
remediation disabled and reported **found no threats**, exit 0. The antivirus
service was enabled; definitions were `1.463.344.0`, updated November 17, 2026,
04:30:26 America/Toronto. Antivirus detection is an additional check, not proof
that malware is absent, particularly for native binaries targeting other systems.

## Functional verification

Archive, file, and source-payload checks are independent of whether a build passes.
Local offline installation, the six installer regression tests, and Windows
`OrtGetApiBase` version query pass. Native builds, inference and exported desktop
smoke checks are recorded in this PR's CI results. Passing CI validates the tested
functionality; it is not a malware certificate.
