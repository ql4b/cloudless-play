# cloudless-play

> **4-line bash script to production API in 5 minutes**

Demonstrates the four-level progression from basic shell scripts to custom Lambda runtimes using cloudless foundational modules.

## Quick Start

### 1. Bootstrap Infrastructure

```bash
mkdir cloudless-play && cd cloudless-play

# Bootstrap foundational modules
curl -sL https://raw.githubusercontent.com/ql4b/cloudless-infra/main/bootstrap | bash
curl -sL https://raw.githubusercontent.com/ql4b/cloudless-app/main/bootstrap | bash

# Configure environment
vim .env  # Set AWS_PROFILE, NAMESPACE, NAME

# Deploy base infrastructure (no resources yet)
export PATH="$(pwd):$PATH"
tf init && tf apply
```

### 2. Add API Infrastructure

Add the REST API module to `infra/main.tf`:

```hcl
module "api" {
  source = "git@github.com:ql4b/terraform-aws-rest-api.git"
  stages = ["staging", "prod"]
  context = module.label.context
  ssm_prefix = local.ssm_prefix
}

output "api" {
  sensitive = true
  value = module.api
}
```

Deploy the API infrastructure:

```bash
tf apply
```

### 3. Configure Serverless Integration

The serverless config automatically references the Terraform-created API:

```yml
# app/serverless.yml (already configured)
provider:
  apiGateway:
    restApiId: ${ssm:/${env:NAMESPACE}/${env:NAME}/${self:provider.stage}/restApiId}
    restApiRootResourceId: ${ssm:/${env:NAMESPACE}/${env:NAME}/${self:provider.stage}/restApiRootResourceId}
```

### 4. Deploy and Test

```bash
cd app
npm ci
npm run deploy -- --stage staging
```

Mark the function as private to require API key:

```yml
# app/sls/functions.yml
events:
  - http:
      private: true
      path: /ip
      method: get
      cors: true
```

Redeploy and test with API key:

```bash
npm run deploy -- --stage staging

# Test with API key
API_KEY=$(cd .. && tf output -json api | jq -r '.api_keys.staging.value')
curl -sS --header "X-Api-Key: $API_KEY" \
  https://YOUR_API_ID.execute-api.REGION.amazonaws.com/staging/ip \
  | base64 -d | jq
```

**Result**: Production API with staging/prod environments, API keys, usage plans, and monitoring.

---

## The Four-Level Progression

### Level 1: Basic Bash + Standard Tools

Start with the simplest possible API - 4 lines of bash:

```bash
#!/bin/bash
data=$(curl -sS "https://httpbin.org/ip")
body=$(printf '%s' "$data" | base64 -w0)
printf '{"statusCode":200,"body":"%s"}' "$body"
```

**When this works**: Simple data fetching, basic transformations, standard Unix tools.
**When it doesn't**: You need `jq`, `imagemagick`, or tools not in base Lambda runtime.

### Level 2: Add Lambda Layers

Need `jq` for JSON processing? Use pre-built layers from [lambda-shell-layers](https://github.com/ql4b/lambda-shell-layers):

```hcl
# infra/main.tf
module "jq_layer" {
  source = "git@github.com:ql4b/lambda-shell-layers.git//jq"
  context = module.label.context
}
```

This creates the layer and stores its ARN in SSM for serverless reference:

```yml
# app/serverless.yml
functions:
  api:
    layers:
      - ${ssm:/${env:NAMESPACE}/${env:NAME}/layers/jq}
    environment:
      PATH: "/opt/bin:${env:PATH}"
```

Now your script can parse JSON properly:

```bash
#!/bin/bash
data=$(curl -sS "https://httpbin.org/ip")
ip=$(echo "$data" | jq -r '.origin')
echo '{"statusCode":200,"body":{"ip":"'$ip'"}}'
```

**Available layers**: `jq`, `qrencode`, `htmlq`, `imagemagick`, `pandoc`, `sqlite`, `yq`

**Build your own layer**:
```bash
# Clone the layers repo
git clone https://github.com/ql4b/lambda-shell-layers.git
cd lambda-shell-layers/jq
./build.sh  # Creates layer zip
```

**The magic**: Same deployment workflow, just added the tool you needed.

### Level 3: Multiple Layers

Need more tools? Stack layers for complex processing:

```hcl
module "qrencode_layer" {
  source = "git@github.com:ql4b/lambda-shell-layers.git//qrencode"
  context = module.label.context
}

module "imagemagick_layer" {
  source = "git@github.com:ql4b/lambda-shell-layers.git//imagemagick"
  context = module.label.context
}
```

```yml
functions:
  api:
    layers:
      - ${ssm:/${env:NAMESPACE}/${env:NAME}/layers/jq}
      - ${ssm:/${env:NAMESPACE}/${env:NAME}/layers/qrencode}
      - ${ssm:/${env:NAMESPACE}/${env:NAME}/layers/imagemagick}
```

Now generate QR codes and process images:

```bash
#!/bin/bash
data=$(curl -sS "https://httpbin.org/ip" | jq -r '.origin')
echo "$data" | qrencode -o /tmp/qr.png
convert /tmp/qr.png -resize 100x100 /tmp/thumb.png
image_data=$(base64 -w0 /tmp/thumb.png)
echo '{"statusCode":200,"body":"'$image_data'","headers":{"Content-Type":"image/png"}}'
```

### Level 4: Custom Runtime (Full Control)

When layers aren't enough, build a custom runtime with any tools:

```dockerfile
# Dockerfile
FROM ghcr.io/ql4b/lambda-shell-runtime:full
RUN apt-get update && apt-get install -y pandoc texlive-latex-base
COPY src/ .
```

Add runtime infrastructure:

```hcl
module "runtime" {
  source = "git@github.com:ql4b/terraform-aws-lambda-runtime.git"
  attributes = ["custom"]
  context = module.label.context
}
```

```yml
# app/serverless.yml
functions:
  api:
    image:
      uri: ${ssm:/${env:NAMESPACE}/${env:NAME}/lambda-runtime-custom/image}
```

Build and deploy:

```bash
REPO_URL=$(tf output -raw runtime.repository_url)
docker build -t $REPO_URL:latest .
docker push $REPO_URL:latest
npm run deploy
```

Now you can do complex document processing:

```bash
#!/bin/bash
echo "$1" | jq -r '.body' | pandoc -f markdown -t pdf -o /tmp/output.pdf
pdf_data=$(base64 -w0 /tmp/output.pdf)
echo '{"statusCode":200,"body":"'$pdf_data'","headers":{"Content-Type":"application/pdf"}}'
```

---

## The Philosophy

Each level maintains the same patterns:
- **Same infrastructure**: API Gateway, usage plans, API keys, monitoring
- **Same deployment**: `npm run deploy`
- **Same bash scripts**: Logic doesn't change, just runtime environment

**Progressive enhancement for infrastructure**: Start simple, add complexity only when value demands it.

## When to Use Each Level

| Level | Use Case | Examples |
|-------|----------|----------|
| **1** | Simple data fetching, basic transformations | Webhook processors, status APIs |
| **2** | JSON processing, HTTP clients | [router-api](https://github.com/ql4b/router-api), weather APIs |
| **3** | Media processing, multi-tool workflows | QR generators, image processors |
| **4** | Complex processing, custom toolchains | PDF generation, scientific computing |

## Related Projects

- **[cloudless-infra](https://github.com/ql4b/cloudless-infra)** - Foundation with consistent labeling
- **[terraform-aws-rest-api](https://github.com/ql4b/terraform-aws-rest-api)** - API Gateway with usage plans
- **[lambda-shell-runtime](https://github.com/ql4b/lambda-shell-runtime)** - Custom Lambda runtime for bash
- **[lambda-shell-layers](https://github.com/ql4b/lambda-shell-layers)** - Pre-built tool layers

---

*Part of the [cloudless](https://cloudless.sh) philosophy: infrastructure that gets out of your way.*