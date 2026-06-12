# Mitthu 🦜

Mitthu is a privacy-first, natively compiled macOS application that tracks your screen time and active windows, categorizes your activities, and provides personalized AI productivity coaching directly on your machine.

---

## Features

- **Automated Activity Tracking**: Automatically tracks the active application and window titles on macOS with sub-second accuracy.
- **Local SQLite Database**: All screen time data is stored securely and privately in a local SQLite database on your Mac.
- **Categorization Rules**: Create pattern-matching rules to automatically group window titles and apps under custom or standard categories (e.g. `Study`, `Work`, `Entertainment`, `Social`).
- **Focus Metrics**: View your focus score calculated from your screen time, and see detailed breakdowns on how you spend your time.
- **Local AI Productivity Assistant**: Chat with a local AI assistant (integrated with Ollama/Llama) that can analyze your screen time to suggest learning and productivity strategies.

---

## Getting Started

### Prerequisites

- macOS 11.0 or later
- Swift / Xcode command line tools

### Installation & Run

1. Clone the repository.
2. Build and compile the app:
   ```bash
   ./build.sh
   ```
3. Open the compiled application:
   ```bash
   open build/Mitthu.app
   ```
4. Access the web dashboard:
   Open your browser and navigate to `http://localhost:5680` to see your tracked data, manage rules, or chat with the local AI.
