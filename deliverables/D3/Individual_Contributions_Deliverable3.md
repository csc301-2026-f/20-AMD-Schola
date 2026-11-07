# YOUR PRODUCT/TEAM NAME - Individual Contributions (D3)

> For each team member: name, role, and specific contributions. Be precise about what you did, not how much you wrote.

**[Name]**, [Role]
> [Specific contributions: features built, PRs reviewed, infrastructure set up, etc.]

**[Name]**, [Role]
> [Specific contributions]

**[Name]**, [Role]
> [Specific contributions]

**[Name]**, [Role]
> [Specific contributions]

**[Name]**, [Role]
> [Specific contributions]

## Sanjay Ram - Developer & Meeting Manager (US1, US3, QA, Meeting Notes)

- Implemented the environment adaptor, connecting Schola's environment API to a ScholaEnvironment scene. This builds on US1's agent adapter. ([PR #34](https://github.com/csc301-2026-f/20-AMD-Schola/pull/34))
- Worked on ([PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35)), with the following changes done:
    - Removed non blocking polling methods from the connector loop based on partner feedback, and only kept the blocking method
    - Set up the gRPC and Protobuf build for Godot
    - Wrote a python scrip thta tbuilds versions in the dependency json for Windows and Linux.
    - Also integrated gRPC configs to our SCons build.
    - Also added macOS configurations as well.
    - Adjusted the CI so it builds the gRPC, and with coordination with Shahyar, integrated a cache to save time with the CI time.
- QA work, reviewing and approving 3 PRs:
    - [PR #33](https://github.com/csc301-2026-f/20-AMD-Schola/pull/33)
    - [PR #38](https://github.com/csc301-2026-f/20-AMD-Schola/pull/38)
    - [PR #40](https://github.com/csc301-2026-f/20-AMD-Schola/pull/40).
- Recorded the minutes for partner meeting 7 and TA meeting 4.
