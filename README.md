# README

# Prerequisites
1. LSC4CE Org with 2GP package installed is available
2. Org must have the permission set licenses "Health Cloud Starter" and "Life Science Commercial"
3. The script runs in a **bash shell** (Linux, macOS, or WSL on Windows)

> **WSL users:** To enable browser-based login, install `wslu` and set the `BROWSER` variable:
> ```bash
> sudo apt-get install -y wslu
> echo 'export BROWSER=wslview' >> ~/.bashrc && source ~/.bashrc
> ```

# Steps to load data into Org
1. Clone the repo to your local machine
2. Open a bash terminal in the `LSStarterConfig` folder
3. Run `npm install`
4. Run the data load script:
   ```bash
   bash Scripts/sh/data_load.sh
   ```
5. The script will guide you through:
   - Installing any missing dependencies automatically
   - Selecting a connected Salesforce org, or logging into a new one
     - When logging in, choose between **Production** (`login.salesforce.com`) or **Sandbox** (`test.salesforce.com`)
   - Deploying profiles, metadata records, config records and trigger handlers
