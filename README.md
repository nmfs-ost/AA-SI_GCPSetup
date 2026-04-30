# 📘 GCP Workstation Setup Guide: **AA-SI Environment**

<p align="center">
  <img src="assets/logo.png" alt="Project Logo" width="70%">
</p>

Welcome! 👋 This guide will walk you through setting up a Google Cloud Platform (GCP) Workstation for use with the **AA-SI (Advanced Acoustics – Scientific Integration)** toolset. The steps below are designed to get you up and running quickly, with screenshots along the way.

---

## ➊ Before You Begin

Before starting, please make sure you have:

1. **A NOAA Gmail account** that is active and accessible.
2. **Authorization to deploy GCP Workstations** hosted by NMFS – Office of Science and Technology.
   - If you don't yet have this access, please start here: [https://github.com/enterprises/noaa-nmfs](https://github.com/enterprises/noaa-nmfs)

---

## ➋ GCP Workstation Configuration

### 1. Navigate to the GCP Workstations Console

Open your browser and go to: [https://console.cloud.google.com/workstations/overview](https://console.cloud.google.com/workstations/overview)

---

### 2. Create a Workstation

Use the interface to configure and deploy a new workstation.

![Create Workstation](assets/instruction_4.png)

---

### 3. Choose a Name, Display Name, and JupyterLab Configuration

Pick something descriptive so you can easily find your workstation later.

![Create Workstation](assets/instruction_6.png)

---

### 4. Launch the Workstation

Once your workstation is created, go ahead and launch it.

![Launch Workstation](assets/instruction_5.png)

---

### 5. Open the Terminal

Start a terminal session inside your running GCP workstation. This is where the rest of the setup happens.

![Open Terminal](assets/instruction_2.png)

---

## ➌ Environment Initialization

### 1. Run the Initialization Script

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

### 2. Authenticate with GCP

Next, sign in with your NOAA credentials and point gcloud at the AA-SI project:

```bash
gcloud auth application-default login && \
gcloud config set account {{ACCOUNT}} && \
gcloud config set project ggn-nmfs-aa-dev-1
```

A link will appear in the terminal — follow it to complete the Google sign-in flow with your NOAA account.

> 📌 **About the placeholders:**
> - `{{ACCOUNT}}` is typically your NOAA email. If you're unsure or run into trouble with this line, you can also try running just the `gcloud auth application-default login` command on its own — the browser sign-in often handles account selection for you.
> - `ggn-nmfs-aa-dev-1` is the shared AA-SI Project ID. Leave it as written.

If your session ever times out, just run the same commands again to re-authenticate.

![Terminal Authentication](assets/instruction_3.png)

---

### 3. Reactivating the Environment Later

Any time you return to your workstation, jump back into the AA-SI environment with:

```bash
source venv312/bin/activate
```

---

## ➍ Using the AA-SI Toolset

### View Available Tools

Once your environment is active, you can explore the full suite of AA-SI functionalities by running:

```bash
aa-find
```

That's it — you're ready to start working! 🎉

---

## ➎ Disclaimer

This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an 'as is' basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or its bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise does not imply endorsement or favoring by the Department of Commerce. Use of DOC seals or logos shall not suggest endorsement by DOC or the U.S. Government.
