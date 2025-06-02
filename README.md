# 📘 GCP Workstation : AA-SI Setup Instructions

This quick guide walks through preparing the GCP Workstation with AA-SI tools.

---

### 💻 Copy & Run

The command below downloads the initialization script, sets permissions, runs it, activates the virtual environment, and starts Google Cloud authentication process👤🔐🌐:

```bash

cd /opt && \
sudo rm -f init.sh && \
sudo wget https://raw.githubusercontent.com/nmfs-ost/AA-SI_GPCSetup/main/init.sh && \
sudo chmod +x init.sh && \
./init.sh && \
cd ~ && \
source aa_si/bin/activate && \
gcloud auth application-default login && \
gcloud config set account {ACCOUNT} && \ 
gcloud config set project ggn-nmfs-aa-dev-1 
```

Follow the browser-based instructions to authenticate using your NOAA Google account.

---

### 🐟 Explore

Run the following to see available operations:

```bash
aa-help
```

This will list available tools, scripts, or modules you can run within the environment.

---

# 📜 Disclaimer
This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an ‘as is’ basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or Department of Commerce bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government.
