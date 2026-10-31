# Logsperity iPhone app

Logsperity by Prosperity Simplified is an iPhone app that helps sales professionals track prospects, closings,
income, expenses and mileage. It comes with **HERB**, an AI business coach you can talk to.

## What's here

| Path | What it is |
|---|---|
| [`HerbFeaturesDesign.md`](HerbFeaturesDesign.md) | The design document (v0.4): screens, logs, calculations, HERB, voice and follow-up questions, decisions and open items |
| [`herb-sim/`](herb-sim/) | A working simulator of the app that runs in a browser, drawn as an iPhone 16, with HERB and a synthetic year of data. See [`herb-sim/README.md`](herb-sim/README.md) |
| [`herb-sim/CONTRACT.md`](herb-sim/CONTRACT.md) | The simulator's architecture and API. The Swift app follows the same rules |
| `tools/` | Developer aids: `converse.py` prints scripted HERB conversations; `dump_office.py` dumps .xlsx/.docx text |

## Try the simulator

Needs Python 3.10 or newer, with no packages to install.

```
cd herb-sim
python server.py      # on a Mac: python3 server.py
```

Open http://localhost:8765 in Edge or Chrome.

Run the tests:

```
cd herb-sim
python -m unittest discover -s tests
```

## Next: the real app on the Mac

The iPhone app is built with SwiftUI and Xcode on a Mac. It uses SwiftData with iCloud, Apple's on-device
Foundation Models for HERB, and Apple In-App Purchase for billing. The app never collects card numbers.
The steps are in [`herb-sim/README.md`](herb-sim/README.md#moving-to-the-mac) and design §23.
