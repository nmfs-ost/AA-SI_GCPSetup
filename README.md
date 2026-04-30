<p align="center">
  <img src="assets/logo.png" alt="AA-SI Logo" width="70%">
</p>

<h1 align="center">📘 GCP Workstation Setup Guide</h1>
<h3 align="center">Advanced Acoustics – Scientific Integration (AA-SI)</h3>

<p align="center">
  <em>A friendly, step-by-step guide to getting your Google Cloud workstation ready for the AA-SI toolset.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white" alt="Python 3.12">
  <img src="https://img.shields.io/badge/Platform-Google%20Cloud-4285F4?logo=googlecloud&logoColor=white" alt="GCP">
  <img src="https://img.shields.io/badge/NOAA-NMFS-005EB8" alt="NOAA NMFS">
</p>

---

## 👋 Welcome!

This guide will walk you through setting up a Google Cloud Platform (GCP) Workstation for use with the **AA-SI (Advanced Acoustics – Scientific Integration)** toolset. Whether this is your first cloud environment or just a refresher, you're in the right place — there are screenshots along the way and helpful tips to keep you on track.

---

## 📑 Table of Contents

- [Before You Begin](#-before-you-begin)
- [GCP Workstation Configuration](#️-gcp-workstation-configuration)
- [Environment Initialization](#️-environment-initialization)
- [Using the AA-SI Toolset](#-using-the-aa-si-toolset)
- [Disclaimer](#-disclaimer)

---

## ✅ Before You Begin

Before starting, please make sure you have:

1. ✉️ **A NOAA Gmail account** that is active and accessible.
2. 🔐 **Authorization to deploy GCP Workstations** hosted by NMFS – Office of Science and Technology.

> 💡 **Don't have access yet?** No worries — start here: [github.com/enterprises/noaa-nmfs](https://github.com/enterprises/noaa-nmfs)

---

## ☁️ GCP Workstation Configuration

### Step 1 — Navigate to the GCP Workstations Console

Open your browser and head to:
🔗 [console.cloud.google.com/workstations/overview](https://console.cloud.google.com/workstations/overview)

---

### Step 2 — Create a Workstation

Use the interface to configure and deploy a new workstation.

<p align="center">
  <img src="assets/instruction_4.png" alt="Create Workstation" width="80%">
</p>

---

### Step 3 — Choose a Name, Display Name, and JupyterLab Configuration

Pick something descriptive so you can easily find your workstation later.

<p align="center">
  <img src="assets/instruction_6.png" alt="Configure Workstation" width="80%">
</p>

---

### Step 4 — Launch the Workstation

Once your workstation is created, go ahead and launch it.

<p align="center">
  <img src="assets/instruction_5.png" alt="Launch Workstation" width="80%">
</p>

---

### Step 5 — Open the Terminal

Start a terminal session inside your running GCP workstation — this is where the rest of the setup happens.

<p align="center">
  <img src="assets/instruction_2.png" alt="Open Terminal" width="80%">
</p>

---

## ⚙️ Environment Initialization

### Step 1 — Run the Initialization Script

This will download and run the AA-SI setup script, set permissions, and activate the Python virtual environment.

Paste the following into your terminal:

```bash
cd && \
sudo rm -f init.sh && \
sudo wget https://raw.githubusercontent.com/nmfs-ost/AA-SI_GPCSetup/main/init.sh && \
sudo chmod +x init.sh && \
./init.sh && \
cd ~ && \
source venv312/bin/activate
```

> 🐍 **Why `venv312`?** Python 3.12 is the version we've standardized on for the AA-SI toolset.

---

### Step 2 — Authenticate with GCP

Next, sign in with your NOAA credentials and point `gcloud` at the AA-SI project:

```bash
gcloud auth application-default login && \
gcloud config set account {{ACCOUNT}} && \
gcloud config set project ggn-nmfs-aa-dev-1
```

A link will appear in the terminal — follow it to complete the Google sign-in flow with your NOAA account.

> 📌 **About the placeholders**
> - `{{ACCOUNT}}` is typically your NOAA email. If you're unsure or run into trouble with this line, try running just the `gcloud auth application-default login` command on its own — the browser sign-in often handles account selection for you.
> - `ggn-nmfs-aa-dev-1` is the shared AA-SI Project ID. Leave it as written.

> ⏰ **Session timed out?** Just run the same commands again to re-authenticate.

<p align="center">
  <img src="assets/instruction_3.png" alt="Terminal Authentication" width="80%">
</p>

---

### Step 3 — Reactivating the Environment Later

Any time you return to your workstation, jump back into the AA-SI environment with:

```bash
source venv312/bin/activate
```

---

## 🧰 Using the AA-SI Toolset

### Explore Available Tools

Once your environment is active, you can explore the full suite of AA-SI functionalities by running:

```bash
aa-find
```

🎉 **That's it — you're ready to start working!**

---

## 📜 Disclaimer

This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an 'as is' basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or its bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise does not imply endorsement or favoring by the Department of Commerce. Use of DOC seals or logos shall not suggest endorsement by DOC or the U.S. Government.

---

<p align="center">
  <em>Made with 🌊 by NOAA NMFS – Office of Science and Technology</em>
</p>
