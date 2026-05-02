# 🛠️ Compute Cluster Forge

**Compute Cluster Forge** is a modular infrastructure-as-code (IaC) framework that leverages **Terraform** to provision secure, auto-healing, and cost-optimized AI/ML compute clusters. While currently configured for **Google Cloud Platform (GCP)**, the architecture is designed for seamless extension to AWS and Azure.

---

## 🌟 Core Architectural Principles

This implementation adheres to industry-standard DevOps practices, moving beyond static scripting toward a dynamic, policy-driven infrastructure:

*   🔒 **Zero-Trust Security (Google IAP):** Implements a strict security model where all public ingress is disabled. Management access (SSH/Web) is limited to authorized users via Google Identity-Aware Proxy (IAP) TCP forwarding.
*   🥷 **Proactive Instance Remediation:** Implements specialized recovery logic in the health probe to detect `ZONE_RESOURCE_POOL_EXHAUSTED` errors. The system automatically purges failing instances and forces the MIG to 'hop' to alternative zones within the region to find available hardware capacity.
*   🩹 **Auto-Healing Spot VM Orchestration:** Leverages Google's cost-effective Spot instances while utilizing Managed Instance Groups (MIGs) with the `ANY` distribution shape and `allow_changing_zone` policy to provide automated cross-zone self-healing.
*   🧠 **VRAM-Optimized AI Features:** Provides turn-key integration for LLM runners (Ollama) and pre-configured model tiers (Gemma4 26B, 31B, E2B). Models are surgically matched to hardware profiles (e.g., L4 GPUs) to ensure 100% VRAM offloading and near-instantaneous inference.
*   🗺️ **Dynamic Infrastructure Discovery:** Implements automated resource discovery. The system queries regional metadata to identify zones supporting specific hardware requirements and restricts deployment to compatible areas.
*   💻 **Cross-OS SSH Orchestration:** Includes an automated PowerShell bridge that natively configures Windows VS Code Remote-SSH profiles with secure IAP ProxyCommands, ensuring seamless connectivity regardless of zone-hopping events.

---

## 📂 Repository Structure

```text
/compute-cluster-forge
├── /modules                # Infrastructure-as-Code (IaC) Modules
│   ├── /aws                # [Planned] AWS Provider Module
│   ├── /azure              # [Planned] Azure Provider Module
│   └── /gcp                # Active GCP Provider Module
│       ├── main.tf         # Resource Orchestration (MIG, Firewalls, APIs)
│       ├── variables.tf    # Input Schema & Secure Defaults
│       ├── outputs.tf      # Validated Resource References
│       └── startup-script.sh # Native Bootstrapping Logic
├── run.sh                  # CLI Orchestration & Execution Wrapper
└── /templates              # Environment & Hardware Profiles
    ├── training.tfvars     # High-compute Base Profile
    ├── inference.tfvars    # Low-latency Base Profile
    ├── spike.tfvars        # General-purpose Burst Profile
    └── gpu-l4.tfvars       # Hardware Layer: NVIDIA L4 GPU / G2 Family
```

---

## 🛠️ Step 1: Prerequisites

Ensure the following toolchains are available in your environment:
1.  **Terraform** (v1.0+)
2.  **Google Cloud CLI (`gcloud`)**
3.  **PowerShell 7+ (`pwsh`)** *(Windows/WSL users only. Required for the orchestrator to automatically bridge WSL and natively configure your Windows VS Code Remote-SSH profiles).*

Authenticate your local machine to generate Application Default Credentials (ADC):
```bash
gcloud auth application-default login
```

---

## 🚀 Step 2: Provisioning Your Cluster

Utilize the `run.sh` orchestrator to provision clusters. The interface supports combining environment templates with hardware layers and runtime variable overrides.

**Example: Provisioning an AI-Ready Cluster with NVIDIA L4 & Gemma4-26B:**
```bash
./run.sh --cloud gcp --type spike --layer gpu-l4 --feature ollama --feature gemma4-26b --var project_id=[PROJECT_ID] --action apply
```

**What happens behind the scenes?**
1.  **Isolation:** Terraform initializes within an isolated workspace.
2.  **Discovery:** Executes dynamic zone discovery based on hardware requirements.
3.  **Provisioning:** Deploys IAM policies, networking, storage, and compute resources.
4.  **Feature Injection:** Dynamically generates startup scripts to install requested software (e.g., Ollama runner) and pull VRAM-optimized models.
5.  **Verification:** Automated status verification monitors the Instance Group until version targets are reached, health checks pass, and features are initialized.
6.  **Reporting:** Generates instance-specific connection strings for secure access.

### 🆔 Configuring Project Identity

You must provide the project id at runtime using one of the following methods:

#### Method A: Environment Variable
Set the standard Terraform environment variable to automatically inject the project id into all forge commands within your current shell session:
```bash
export TF_VAR_project_id="your-gcp-project-id"
./run.sh --cloud gcp --type spike --action apply
```

#### Method B: CLI Override
Pass the project id directly using the `--var` flag:
```bash
./run.sh --cloud gcp --type spike --var project_id="your-gcp-project-id" --action apply
```

---

## 💻 Step 3: Cluster Interaction

Internal services must be accessed through the established IAP tunnel.

### ⚠️ Important: Network Binding Requirement
To ensure accessibility via IAP TCP forwarding, all applications (e.g., Jupyter Lab, Tensorboard) **MUST** bind to **`0.0.0.0`**. Applications listening exclusively on `127.0.0.1` will be unreachable.

*   ✅ **Jupyter Lab:** `jupyter lab --ip=0.0.0.0 --port=8888 --no-browser`
*   ✅ **HTTP Server:** `python3 -m http.server 8080 --bind 0.0.0.0`

### 🌐 Connection Reference

Once the cluster is live, `run.sh` provides dynamically resolved connection commands:

**Secure SSH Access:**
```bash
gcloud compute ssh [INSTANCE_NAME] --tunnel-through-iap --project=[PROJECT_ID] --zone=[ZONE]
```

**IAP Port Forwarding (Remote 8888 ➔ Local 8888):**
```bash
gcloud compute start-iap-tunnel [INSTANCE_NAME] 8888 --local-host-port=localhost:8888 --project=[PROJECT_ID] --zone=[ZONE]
```

#### 🔄 Note on Zone-Hopping & SSH Persistence
Because the architecture utilizes **Proactive Instance Remediation**, an instance may be recreated in a different zone if the original zone experiences resource exhaustion. Since the VS Code `ProxyCommand` is zone-dependent, a "Zone-Hop" will cause existing SSH config entries to become obsolete. To restore connectivity, simply re-run the `apply` command (or the automated PowerShell bridge) to surgically update your local `.ssh/config` with the new instance location.

---

## 🔥 Step 4: Resource Decommissioning

To prevent unnecessary billing, decommission all provisioned resources upon task completion:

```bash
./run.sh --cloud gcp --type spike --layer gpu-l4 --var project_id=[PROJECT_ID] --action destroy
```

> **🛑 Safety Note:** This operation performs a forceful deletion of all regional resources, including the stateful GCS bucket. Ensure all datasets and trained models are synchronized to local storage prior to execution.
