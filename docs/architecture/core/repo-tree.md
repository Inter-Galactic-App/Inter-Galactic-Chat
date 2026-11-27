# Repository Tree

Snapshot of the app repository's stable top-level structure. Treat this as an
orientation aid, not generated output.

```text
repo-root/
├── .github/
├── .vscode/
├── archive/
├── docs/
│   ├── architecture/
│   │   ├── calls-streaming-audio/
│   │   ├── core/
│   │   │   ├── codebase-map.md
│   │   │   ├── overview.md
│   │   │   └── repo-tree.md
│   │   ├── diagnostics/
│   │   ├── features/
│   │   ├── matrix/
│   │   ├── notifications/
│   │   ├── release/
│   │   └── README.md
│   └── adr/
│       ├── 0001-stay-matrix-native.md
│       ├── 0002-preserve-e2ee-session-integrity.md
│       └── 0003-plugin-strategy.md
├── fastlane/
├── intergalactic/
│   ├── android/
│   ├── ios/
│   ├── lib/
│   ├── linux/
│   ├── macos/
│   ├── web/
│   ├── windows/
│   ├── assets/
│   ├── scripts/             App build, test and release tooling
│   ├── pubspec.yaml         App package manifest
│   └── analysis_options.yaml
├── plugins/
├── scripts/                 Repository CI and validation tooling
├── tiamat/
├── tools/
├── widgets/
├── PUBLIC_CHANGELOG.md
├── README.md
├── pubspec.yaml             Pub workspace manifest (not the app package)
├── pubspec.lock
└── devtools_options.yaml
```

Two names appear twice and mean different things:

- `pubspec.yaml` at the root is the pub *workspace* manifest;
  `intergalactic/pubspec.yaml` is the app package.
- `scripts/` at the root is repository CI tooling (`scripts/ci/`);
  `intergalactic/scripts/` is app build, test and release tooling.
