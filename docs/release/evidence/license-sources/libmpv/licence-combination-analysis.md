# AGPL application + libmpv — licence combination

Prepared by S&C, 2026-08-07. **Not legal advice. Treat as an open legal question either way — this is not
settled and should not be presented as settled.**

## Short answer

**The combination you asked me to test does not arise.** You asked whether an AGPLv3
application can incorporate a GPLv2-or-later libmpv, reasoning that "or later" permits taking
mpv as GPLv3 and that AGPLv3 §13 is designed for exactly that pairing.

**Your reasoning was sound**, and had the premise held I would have agreed with it. But the
shipped `libmpv-2.dll` is **LGPLv2.1-or-later**, not GPL (see `LICENCE-DETERMINATION.md`). The
actual combination is AGPLv3 application + LGPL library, which is materially easier and raises
none of the tension you were bracing for.

## Testing your reading, on its own terms

Had the DLL been a GPL build, the analysis would have run like this — and it comes out where
you expected.

**Factors supporting the combination:**

- mpv's default licence is GPL **version 2 or later**. The "or later" clause is a grant to the
  recipient, so taking the code as GPLv3 is the licensee's election and needs no upstream
  permission.
- AGPLv3 §13 is explicitly bidirectional with GPLv3: it permits linking AGPLv3 work with
  GPLv3 work, with each part retaining its own licence. The FSF added §13 for precisely this
  interoperability problem.
- GPLv3 §13, the mirror provision, grants the same permission from the GPL side.
- The FSF's own compatibility matrix treats AGPLv3 and GPLv3 as combinable on this basis.

**Factors cutting against, or needing care:**

- The route depends entirely on the "or later" clause. A GPLv2-**only** dependency would not
  work, because GPLv2 has no §13 and is not compatible with AGPLv3. So the argument is not
  general; it is specific to mpv's "or later" grant.
- §13 permits the *combination*; it does not merge the licences. The AGPL's network-use
  obligation would attach to the AGPL portion, and each part keeps its own terms. That is a
  compliance-shaped outcome, not a free pass.
- Every GPL-gated mpv component would then be in scope, expanding the corresponding-source
  obligation.
- Distribution through app stores would need checking for anti-tivoisation and additional-terms
  friction, which is where GPLv3-family combinations usually get uncomfortable in practice.

**Conclusion on your reading:** workable rather than prohibited, as you thought, and for the
reason you gave. I do not disagree with you. It is simply moot here.

## The combination that actually applies

**AGPLv3 application dynamically loading an LGPL library**, where the library is
LGPLv2.1-or-later (mpv) statically containing LGPLv3-or-later (FFmpeg n6.0) and a set of
permissive components.

**Factors supporting:**

- The LGPL is designed for exactly this. Its whole purpose is to let a library be used by an
  application under a different licence, including a proprietary one — and AGPLv3 is a far
  easier case than proprietary.
- `libmpv-2.dll` is a **separate DLL loaded at run time**. The LGPLv2.1 §6 / LGPLv3 §4
  relinking requirement — that a user can substitute a modified library — is satisfied by
  construction. Nothing extra is needed.
- The internal stack is self-consistent: mpv is LGPLv2.1+, so it can be taken as LGPLv3 where
  needed to sit alongside the LGPLv3+ FFmpeg. The `--enable-version3` election is what makes
  the FFmpeg component set coherent, and it does not propagate outward to the application.
- No application source obligation arises from the LGPL. The AGPL obligations the project
  already carries are unchanged by libmpv's presence.

**Factors needing care:**

- The LGPL obligations that *do* apply were entirely unmet when this was written and are now
  **partly met** (status as at 2026-08-08): the mpv corresponding source is published and
  digest-verified against the served file; the notice text exists in
  `THIRD_PARTY_NOTICES.libmpv.md`. **Updated 2026-08-09:** the FFmpeg `n6.0` archive is now
  **published** (2026-08-08), and so are this DLL's three obligated components — `libfribidi`
  1.0.13, `libsoxr` 0.1.3 and `uchardet` — at their own pins. Still outstanding: **this DLL's**
  build definition could not be recovered and no substitute is offered; per-component licence
  texts for the attribution-only components are not collected; and this DLL's transitive
  dependencies are not enumerable. That is the live issue, and it is a real one — it simply is
  not the GPL issue the task assumed.
- **MuJS — resolved for this artefact, 2026-08-08. It is ISC, and it is not a risk here.**
  An earlier revision of this section called MuJS "the one genuine risk", on the reasoning
  that MuJS relicensed from ISC to AGPL-3.0 and that the compiled-in version was not
  recoverable from the binary. **That reasoning is withdrawn.** The version does not need to
  be recovered from the binary, because it can be bounded by date: this artefact's own
  `libjpeg-turbo version 3.0.1 (build 20230924)` string puts its build on or about
  2023-09-24, and MuJS 1.3.4 is dated 2023-11-21, so **1.3.3 (2023-01-10) is the highest tag
  that could be present**. Every tag from 1.0.0 through 1.3.3 carries the ISC Licence
  ("Copyright (c) 2013-2020 Artifex Software, Inc.") in both `ccxvii/mujs` and
  `ArtifexSoftware/mujs`, so an untagged snapshot between them does not change the answer.
  libmpv therefore does **not** contain an AGPL component, and the "LGPL library" description
  is complete. The bound cannot move with future upstream relicensing. Recorded per-entry in
  `THIRD_PARTY_LICENSES.libmpv.json`.

  Not claimed here: that MuJS is ISC-only *as a project today*. Artifex dual-licenses it
  commercially, and that is a live question about the project — it is simply not a question
  about this artefact, and it does not depend on the build-definition gap. See open legal question 3.
- **uchardet** is tri-licensed MPL-1.1 / GPL-2.0+ / LGPL-2.1+. The project should elect and
  record an arm. Electing GPL-2.0 would be an unforced error; MPL-1.1 or LGPL keeps the
  artefact consistent.
- App-store distribution of LGPL components still needs its own check, independent of this
  analysis.

## The open legal questions

1. Confirm the LGPL determination and that `-Dgpl=false` plus the absent `vo_direct3d` is
   sufficient evidence — this reverses a previously recorded finding, so it should be checked
   rather than accepted.
2. Confirm no application-source obligation arises, given the dynamic-load architecture.
3. **MuJS**: *narrowed 2026-08-08.* Which arm applies to **this artefact** is no longer open —
   it is bounded to `<= 1.3.3`, which is ISC. What remains open is whether Artifex's
   commercial dual-licensing of MuJS as a project today raises anything for us, given that we
   redistribute a pre-2023-09-24 ISC snapshot compiled into a third-party binary.
4. **uchardet**: elect an arm and record it.
5. Whether the mingw-w64 runtime belongs in the notice or is properly treated as toolchain.
6. Whether the existing app-store distribution route raises anything separate for LGPL
   components.

I have not treated any of the above as settled.
