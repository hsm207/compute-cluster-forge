# 🛠️ Compute Cluster Forge

Welcome to **Compute Cluster Forge**! This tool allows you to spin up highly secure, auto-healing, and cost-effective AI/ML compute clusters on demand. Currently, this project is configured for **Google Cloud Platform (GCP)**, but the repository is architected to easily expand to AWS and Azure.

---

## 🌟 High-End DevOps Features

This isn't a standard, brittle Terraform script. It implements industry-standard DevOps practices:

*   🔒 **Zero-Trust Security (Google IAP):** Instead of messing with public IPs or VPNs, this uses Google Identity-Aware Proxy. The firewall blocks all public traffic and only allows SSH and web connections tunneled through Google's secure OAuth servers.
*   🩹 **Auto-Healing Spot Instances:** By using an Instance Group Manager, we use Google's cheapest Spot VMs (saving up to 80%). If Google reclaims the VM, the Manager automatically spins up a replacement to resume your workload.
*   🧠 **Self-Aware Hardware Discovery:** No more hardcoded zones! The forge dynamically queries Google Cloud to find out exactly which zones support your requested hardware (e.g., L4 GPUs) and restricts deployments only to those areas.
*   🥞 **Layered Configuration:** Mix and match base templates with specific hardware layers (like GPUs) using an intuitive CLI interface.
*   ⚙️ **Context-Aware Metadata:** If you request a GPU layer, the forge automatically injects flags to silently install NVIDIA CUDA drivers on boot. If you request CPU only, the metadata stays perfectly clean.
*   🔄 **Persistent Data Sync:** A dedicated Google Cloud Storage (GCS) bucket is spun up alongside your cluster for seamless data persistence.

---

## 📂 Repository Structure

```text
/compute-cluster-forge
├── /modules                # The "How" (Cloud-specific Infrastructure)
│   ├── /aws                # Placeholder for AWS expansion
│   ├── /azure              # Placeholder for Azure expansion
│   └── /gcp                # Active GCP setup
│       ├── main.tf         # Core logic (Instance Groups, Firewalls, Data Sources)
│       ├── variables.tf    # Accepted inputs & secure defaults
│       ├── outputs.tf      # Console outputs
│       └── cloud-init.yaml # Server software setup script
├── run.sh                  # The intelligent execution wrapper script
└── /templates              # The "What" (Cluster configurations)
    ├── training.tfvars     # High CPU base configuration
    ├── inference.tfvars    # Low latency base configuration
    ├── spike.tfvars        # Cheap, burst CPU base configuration
    └── gpu-l4.tfvars       # Hardware Layer: NVIDIA L4 GPU & G2 Machine
```

---

## 🛠️ Step 1: Prerequisites

Before you forge your first cluster, ensure you have these standard tools installed:
1.  **Terraform** (v1.0+)
2.  **Google Cloud CLI (`gcloud`)**

Once installed, authenticate your local machine with Google Cloud to generate your Application Default Credentials (ADC):
```bash
gcloud auth application-default login
```
*(This will securely pop open a web browser for authorization).*

---

## 🚀 Step 2: Spin Up Your Cluster

To create your cluster, use the `run.sh` script. Our **Intelligent Interface** allows you to combine base templates, hardware layers, and runtime variable overrides in a single command!

**Example: Forging a Spike Cluster with an L4 GPU:**
```bash
./run.sh --cloud gcp --type spike --layer gpu-l4 --var project_id=your-gcp-project-id --action apply
```

**What happens behind the scenes?**
1.  Terraform safely initializes in an isolated workspace.
2.  It dynamically discovers valid zones for your hardware and builds the IAP firewall, GCS bucket, and Instance Group Manager.
3.  The script **patiently waits** for Google to boot the VM, install drivers, and pass health checks.
4.  The script prints a clean summary with the exact `gcloud` commands needed to connect.

---

## 💻 Step 3: Working on Your Cluster

Instead of using a standard IP address, you will connect securely via Google's IAP tunnel.

### ⚠️ Important: Application Binding Caveat
For any web app or service (like Jupyter Lab) to be accessible via the IAP tunnel, it **MUST** listen on all network interfaces (**`0.0.0.0`**), not just `localhost` or `127.0.0.1`. 

*   ✅ **Jupyter Lab Example:** `jupyter lab --ip=0.0.0.0 --port=8888 --no-browser`
*   ✅ **Python HTTP Server Example:** `python3 -m http.server 8080 --bind 0.0.0.0`

*If your app is only listening on `localhost`, Google's IAP tunnel will fail with a `failed to connect to backend` error!* ❌

### 🌐 Connection Commands

Once the cluster is live, `run.sh` will provide dynamically generated, 1:1 mapped connection commands specific to your live VM instance.

**To SSH into the machine:**
```bash
gcloud compute ssh hpc-node-abcd --tunnel-through-iap --project=your-gcp-project-id --zone=us-central1-a
```

**To access Jupyter Lab (Remote Port 8888 ➔ Local Port 8888):**
```bash
gcloud compute start-iap-tunnel hpc-node-abcd 8888 --local-host-port=localhost:8888 --project=your-gcp-project-id --zone=us-central1-a
```
*(Then simply open `http://localhost:8888` in your local web browser!)*

---

## 🔥 Step 4: Tear Down (Stop the Billing!)

When your experiment or training is complete, ensure you don't leave the cluster running. Destroy it entirely with one automated command:

```bash
./run.sh --cloud gcp --type spike --layer gpu-l4 --var project_id=your-gcp-project-id --action destroy
```

> **🛑 Safety Note:** This will forcefully destroy the Compute instances and the attached GCS Storage Bucket. Ensure you have downloaded any trained models or data to your local machine before running the destroy command!
