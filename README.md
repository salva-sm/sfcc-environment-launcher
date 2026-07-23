# SFCC Sandbox Launcher

An automated Bash script to spin up a Salesforce Commerce Cloud (SFCC) On-Demand Sandbox, open Visual Studio Code, monitor sandbox readiness, and launch Business Manager upon completion.

## 🚀 Demo

Here is a quick overview of how the launcher initializes the environment, validates authentication, and starts the sandbox:

<p align="center">
  <img src="./assets/demo.png" alt="SFCC Environment Launcher Demo" width="800">
</p>

> ℹ️ **Note:** When executed via the automated Windows Task, the script runs silently in the background (headless). The terminal UI shown above won't pop up, but VS Code and Business Manager will open automatically when ready. To see live execution logs, run `./start_environment.sh` manually.

---

## ✨ Features

* 🔐 **Automated Authentication:** Authenticates with `sfcc-ci` using API client credentials.
* 🚀 **Sandbox On-Demand Start:** Triggers the sandbox boot process asynchronously.
* 💻 **Workspace Integration:** Launches VS Code in your specified local project directory.
* ⏳ **Real-Time Polling:** Monitors sandbox state changes (`stopped` ➔ `started`) via `sfcc-ci`.
* 🌐 **Browser Auto-Launch:** Automatically opens Business Manager once the instance is fully running.
* ⚙️ **Windows Automation:** Optionally register a Windows Scheduled Task to run everything on system logon.

---

## 🛠️ Prerequisites

Ensure the following tools are installed on your machine:

* [Node.js](https://nodejs.org/) (v16+ recommended)
* [Git Bash](https://gitforwindows.org/) (for Windows environments)
* [Visual Studio Code](https://code.visualstudio.com/) (with `code` command added to `PATH`)

---

## ⚙️ Setup & Configuration

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/salva-sm/sfcc-environment-launcher.git](https://github.com/salva-sm/sfcc-environment-launcher.git)
   cd sfcc-sandbox-launcher
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Configure Environment Variables:**
   Create a `.env` file in the root folder using your SFCC API credentials:
   ```env
   SFCC_REALM=your_realm
   SFCC_INSTANCE=your_instance_number
   LOCAL_PROJECT_PATH=C:/Users/your-user/Github/your-repo
   ```

---

## 🔄 Windows Logon Automation (Optional)

You can configure Windows to run this script automatically every time you log in to your machine.

> ⚠️ **IMPORTANT (Administrator Required):** To install or remove the Scheduled Task, you **must run terminal as Administrator**. Otherwise, Windows will block the command due to insufficient privileges.

### Option 1: Via PowerShell (Recommended)
Open PowerShell as **Administrator** and run:

```powershell
.\install.ps1
```

### Option 2: Via Command Prompt (CMD)
Open CMD as **Administrator** and run:

```cmd
powershell -ExecutionPolicy Bypass -File install.ps1
```

### Option 3: Via NPM Shortcuts
```bash
# Install the task
npm run task:install

# Remove the task
npm run task:remove
```

---

## 📜 NPM Scripts Reference

The `package.json` file includes convenient shortcuts to simplify script execution and setup:

| Command | Description |
| :--- | :--- |
| `npm start` | Executes `start_environment.sh` to trigger authentication, sandbox startup, VS Code, and polling. |
| `npm run sfcc:auth` | Runs local `sfcc-ci` authentication directly without starting the sandbox. |
| `npm run task:install` | Registers the logon automation task in Windows Scheduled Tasks (**Requires Admin**). |
| `npm run task:remove` | Unregisters and deletes the `SFCC_Sandbox_Launcher` scheduled task (**Requires Admin**). |