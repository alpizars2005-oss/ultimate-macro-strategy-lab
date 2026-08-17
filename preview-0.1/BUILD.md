# Preview 0.1 build manifest

Baseline: official Ultimate Macro 1.3.3.

Local integration verification before packaging:

- `python -m pytest -q`
- Result: **5 passed**

The tests cover Editor/Stats wiring, reward tracking without a webhook, Roblox-window screen-offset handling for result OCR, conservative coordinate rewrites across the bundled official strategies, and preservation of 1.3.3/future non-placement actions.

Package SHA-256:

`028ef40095a8be063772b1c0036797fec0fd8383bbdc48bb91af58bdd9470821  Ultimate_Macro_Strategy_Lab_0.1.zip`

Key integrated source hashes:

```text
1346988914c21ae405bca87a8c7fc52f68ed5546b911235d708d84da3e2d2fae  Main_Lab.ahk
86fa0a41fbb01155dd7fd85350d244f9289ed22413b792b449255b1e84cd3b43  submacros/watchdog_lab.ahk
d1b57edab28ced4636e259e4a86ba874552673dd9da3f130e91dba3c6ef565f1  lib/StrategyLab/RewardTrackerCore.ahk
20618a93d16f6ac8f99d4dc5a4a09e4b30c7cf40dd63ef62a218c01a9441cc26  lib/StrategyLab/RewardTrackerTab.ahk
1a0547f0d0d4b14ddf31cd83ca5135b99ec58028dcc12bf05e7d2dd75c3e97cc  lib/StrategyLab/StrategyEditorCore.ahk
29c622a85939db8d3b9f44f688f966743cc701086e3ebc03eec0e0aae3495ee7  lib/StrategyLab/StrategyEditorTab.ahk
```

The complete Windows test ZIP contains the official 1.3.3 runtime/resources plus the Lab files. The repository stores the Lab source and clean patches separately so upstream baseline code stays easy to distinguish from experimental work.
