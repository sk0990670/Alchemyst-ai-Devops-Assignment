# Distributed AI Inference on AWS

This project provisions a distributed AI inference architecture on AWS using Terraform. It deploys two EC2 instances across public and private subnets, utilizing the `iii` RPC engine for cross-language worker communication.

## 🏗️ Architecture
<img width="1536" height="1024" alt="ChatGPT Image May 20, 2026, 01_58_53 PM" src="https://github.com/user-attachments/assets/2e54d8af-2b39-42fb-a5a1-ec9feecb2942" />

**Two workers, two VMs:**
- **inference-worker (Python):** Hosted in the private subnet. Loads `gemma-3-270m` GGUF model and runs inference via the RPC function `inference::run_inference`.
- **caller-worker (TypeScript):** Hosted in the public subnet. Acts as the API Gateway with an HTTP trigger on `POST /v1/chat/completions`. It calls the inference worker via RPC and returns a JSON response.

---

## 🛠️ Step-by-Step Deployment Explanation

The infrastructure is fully automated using Terraform. Here is a breakdown of what the code does and *why*:

### 1. The Network (VPC + Subnets)
We provision an isolated network (VPC). 
- **Public Subnet:** Has an Internet Gateway attached. This is where the Caller VM lives so it can accept public HTTP requests.
- **Private Subnet:** Has NO internet access, only a NAT Gateway. This is where the Inference VM lives. It can reach out to the internet to download the Python model, but nobody on the internet can reach in. This ensures strict network hygiene.

### 2. Security Groups (Firewalls)
- **API Gateway SG (Public):** Opens TCP port 3111 to the world (`0.0.0.0/0`) for the API, and TCP 22 (SSH) strictly to your specific IP address.
- **Inference SG (Private):** Completely blocked from the internet. It only opens port 49134 (for the RPC engine) and port 22 (for SSH) to the specific private IP of the Caller VM.

### 3. The EC2 Instances
- **Caller VM (`t3.micro`):** Extremely lightweight (1GB RAM) because it only runs a Node.js web server.
- **Inference VM (`c7i-flex.large`):** Requires at least 4GB of RAM because loading the PyTorch framework and the 8-bit quantized Gemma model (~270MB) requires significant memory overhead.

### 4. Bootstrapping (user_data)
When Terraform launches the VMs, it runs bash scripts automatically:
- It installs Node.js / Python3.
- It installs the `iii` RPC engine.
- It clones this repository and installs `npm` and `pip` dependencies.
- It configures `systemd` services so that the API and Inference workers start automatically and restart on failure.

---

## 🚀 How to Deploy from Scratch

1. **Find your Public IP:**
   Go to [https://checkip.amazonaws.com/](https://checkip.amazonaws.com/). This is required to whitelist your IP for SSH access.

2. **Clone this repository:**
   ```bash
   git clone <YOUR_REPO_URL>
   cd terraform
   ```

3. **Configure Terraform Variables:**
   Create a `terraform.tfvars` file (this is ignored by git for security) and add your public IP (with a `/32` CIDR block) and your AWS SSH key pair name:
   ```hcl
   your_ip_cidr = "YOUR_PUBLIC_IP/32"  # e.g., "49.47.135.128/32"
   key_pair_name = "Batch12"           # Must exist in AWS ap-south-1
   ```

4. **Deploy the infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply -auto-approve
   ```

5. **Wait for Bootstrap:**
   Wait ~10 minutes for the VMs to fully bootstrap (install dependencies, download the model, and start the systemd services).

---

## 🧪 API Usage

Once deployed, Terraform will output a `curl_example` command. Run it to test the API:

**Request:**
```bash
curl -X POST http://<CALLER_VM_PUBLIC_IP>:3111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'
```

**Example Response:**
```json
{
  "result": {
    "success": "You've connected two workers...",
    "response": "4"
  }
}
```

---

## 🐛 Debugging & Fixes (May 2026)

During the deployment of this assignment, the developers of the `iii` engine released a major breaking update (`v0.12.0`). This caused the out-of-the-box quickstart scripts to fail in three critical ways, which have all been successfully debugged and fixed in this repository:

1. **Broken `iii` CLI Installation Path:**
   - **Issue:** The installation path for the engine silently changed from `/root/.iii/bin` to `/root/.local/bin`. This broke our `systemd` services because the binaries were no longer where they were expected to be, resulting in continuous `status=203/EXEC` restart loops.
   - **Fix:** Updated the Terraform `user_data` boot scripts (`caller_setup.sh` and `inference_setup.sh`) to automatically move the newly installed binaries to `/usr/local/bin`, ensuring `systemd` can securely execute them as the `ubuntu` user.

2. **Network Binding Issue (`ECONNREFUSED`):**
   - **Issue:** The Caller VM could not connect to the Inference VM over the private subnet because the new engine defaulted to binding exclusively to `127.0.0.1` (localhost).
   - **Fix:** Injected explicit `engine: { host: 0.0.0.0 }` configurations directly into the `config.yaml` of both VMs during bootstrap, exposing the RPC WebSockets to the VPC network safely.

3. **Incompatible Worker SDKs:**
   - **Issue:** The worker templates were hardcoded to use `iii-sdk` v0.11.0, which silently crashes when communicating with the v0.12.0 engine.
   - **Fix:** Directly patched `quickstart/workers/caller-worker/package.json` to use `"iii-sdk": "^0.12.0"` and `quickstart/workers/inference-worker/requirements.txt` to use `iii-sdk>=0.12.0`.

---

## 🔒 Production Hardening & Scaling

**What I'd harden for production:**
To make this enterprise-ready, I would place an Application Load Balancer (ALB) with AWS ACM certificates in front of the Caller VM to enable HTTPS/TLS. I'd add API authentication (like JWTs or API keys) to the TypeScript worker to prevent unauthorized access. The Inference VM would remain strictly isolated in the private subnet, but I would use AWS Systems Manager (SSM) Session Manager for shell access instead of SSH, completely eliminating the need to expose port 22.

**If the model were 100x larger (e.g., Llama 70B):**
A much larger model cannot run on CPU. I would swap the `c7i-flex.large` instance for a GPU-backed instance like `g5.2xlarge` or `p4d.24xlarge`. To handle traffic spikes, I would put the Inference VMs in an Auto Scaling Group (ASG) behind an internal load balancer. Finally, instead of downloading the massive model from HuggingFace on every boot, I would cache the model weights on an Amazon EFS volume or an S3 bucket with a VPC endpoint for ultra-fast, local network retrieval.

---

## 📸 Deployment Evidence

*(Add your screenshots here before submission)*

1. **VPC & Subnets:**
   ![VPC Setup]<img width="2158" height="1185" alt="Screenshot 2026-05-20 134524" src="https://github.com/user-attachments/assets/09a26cc7-4d71-4564-bc6d-dcab2b6b67f8" /><img width="2159" height="1195" alt="Screenshot 2026-05-20 134546" src="https://github.com/user-attachments/assets/57e42105-158d-4004-8d1f-97ee2d7ae8f7" />



2. **Running EC2 Instances:**
   ![EC2 Instances]<img width="2159" height="1192" alt="image" src="https://github.com/user-attachments/assets/9139b4ad-b97c-4fb7-8810-fed10d7d138f" />


3. **Security Groups of Caller VM and Inference VM(Inbound Rules):**
   ![Security Groups]<img width="2159" height="1190" alt="image" src="https://github.com/user-attachments/assets/4fc75d25-b4cd-4f13-812e-f7a22b0f395d" /><img width="2159" height="1187" alt="image" src="https://github.com/user-attachments/assets/760d8792-80fe-476d-9f95-5c18fa1cafa8" />



5. **terraform apply output:**
   ![Termianl Output]<img width="1414" height="723" alt="Screenshot 2026-05-20 134309" src="https://github.com/user-attachments/assets/22f51445-46c2-47d9-abd8-9e4dcc4d60ca" />



4. **Successful API Response (cURL):**
   ![cURL Test](link_to_screenshot)
