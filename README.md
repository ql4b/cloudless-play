# cloudless-play

## Bootstrap foundations

Boootstap `cloudless-infra` and `cloudless-app`

```bash
mkdir cloudless-play
cd cloudless-play
curl -sL https://raw.githubusercontent.com/ql4b/cloudless-infra/main/bootstrap | bash
curl -sS -L https://$GITHUB_TOKEN@raw.githubusercontent.com/ql4b/cloudless-app/refs/heads/main/bootstrap \
    | bash -s main
```

Edit .env

```bash
export PATH="$(pwd):$PATH"
tf init
tf apply --auto-approve
```

You haven't actually deployed any resource ...

Add the api tf module

```hcl
module "api" {
  source = "git@github.com:ql4b/terraform-aws-rest-api.git?ref=next"
  stages = ["staging", "prod"] # defaults
  context = module.label.context
  ssm_prefix = local.ssm_prefix
}

output api {
    sensitive = true
    value = module.api
}
```

Provision it 

```bash
tf init
tf apply
```

Configure your serverless service

```yml
# serverless.yml
provider:
  apiGateway:
    restApiId: ${ssm:/${env:NAMESPACE}/${env:NAME}/${self:provider.stage}/restApiId }
    restApiRootResourceId: ${ssm:/${env:NAMESPACE}/${env:NAME}/${self:provider.stage}/restApiRootResourceId}
```

```bash
cd app
npm ci
npm run deploy -- --stage staging
```

Use API keys 

```yml
# sls/functions.yml
events:
  - http:
    private: true
    path: /ip
    method: get
    cors: true
```
```bash
npm run deploy -- --stage staging

API_KEY=$(tf output -json api | jq -r  .api_keys.staging.value)
curl -sS \
   --header "X-Api-Key: $API_KEY" \
  https://nqn2n1rosi.execute-api.eu-south-2.amazonaws.com/staging/ip \
  | base64 -d | jq 
```

## Level 1: Basic Bash + Standard Tools

The `run.sh` script uses only standard Lambda runtime tools:

```bash
#!/bin/bash
data=$(curl -sS "https://httpbin.org/ip")
body=$(printf '%s' "$data" | base64 -w0)
printf '{"statusCode":200,"body":"%s"}' "$body"
```

This works great until you need tools not available in the standard runtime.

## Level 2: Add Lambda Layers

Need `jq` for JSON processing? Add a layer:

```hcl
# infra/main.tf
module "jq_layer" {
  source = "git@github.com:ql4b/lambda-shell-layers.git//jq"
  context = module.label.context
}
```

```yml
# serverless.yml
functions:
  api:
    layers:
      - ${ssm:/${env:NAMESPACE}/${env:NAME}/layers/jq}
    environment:
      PATH: "/opt/bin:${env:PATH}"
```

Now your script can use `jq`:

```bash
#!/bin/bash
data=$(curl -sS "https://httpbin.org/ip")
ip=$(echo "$data" | jq -r '.origin')
echo '{"statusCode":200,"body":'{"ip":"'$ip'"}'}'
```

## Level 3: Multiple Layers

Need more tools? Stack layers:

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

Generate QR codes, process images, parse JSON - all in bash.

## Level 4: Custom Runtime (Full Control)

When layers aren't enough, build a custom runtime:

```dockerfile
# Dockerfile
FROM ghcr.io/ql4b/lambda-shell-runtime:full
COPY src/ .
```

```hcl
# Add runtime infrastructure
module "runtime" {
  source = "git@github.com:ql4b/terraform-aws-lambda-runtime.git"
  attributes = ["custom"]
  context = module.label.context
}
```

```yml
# serverless.yml
functions:
  api:
    image:
      uri: ${ssm:/${env:NAMESPACE}/${env:NAME}/lambda-runtime-custom/image}
```

Build and deploy:

```bash
# Build custom runtime
REPO_URL=$(tf output -raw runtime.repository_url)
docker build -t $REPO_URL:latest .
docker push $REPO_URL:latest

# Deploy function
npm run deploy
```

## The Progression

1. **Level 1**: Standard runtime - `curl`, `base64`, basic tools
2. **Level 2**: Single layer - Add `jq` for JSON processing  
3. **Level 3**: Multiple layers - Stack specialized tools
4. **Level 4**: Custom runtime - Full control, any tools

Each level adds capability while maintaining the same deployment workflow. Start simple, scale complexity only when needed.

## Real Examples

- **router-api**: Level 2 (jq + http-cli layer)
- **qr-generator**: Level 3 (jq + qrencode + imagemagick)
- **document-processor**: Level 4 (custom runtime with pandoc + latex)

The beauty: same infrastructure, same deployment, different capabilities. 




