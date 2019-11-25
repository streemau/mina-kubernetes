# mina-kubernetes
Plugin for the [mina](https://github.com/mina-deploy/mina) deployment tool to streamline deployment of resources to Kubernetes clusters, using the [kubernetes-deploy](https://github.com/Shopify/kubernetes-deploy) gem and [mina-multistage](https://github.com/endoze/mina-multistage) plugin.

Requires local Docker and [kubectl](https://cloud.google.com/kubernetes-engine/docs/quickstart) with local authentication set up to connect to the destination Kubernetes cluster as context in your local KUBE_CONFIG. See https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#generate_kubeconfig_entry for example with Google Kubernetes Engine.

NB: `docker manifest inspect` is used to check whether the Docker image with requested tag is available. This requires experimental features to be enabled in your local Docker config by adding `"experimental": "enabled"` to `~/.docker/config.json`.
If the image repository is not public authentication will need to be set up for your local Docker, for instance see https://cloud.google.com/container-registry/docs/advanced-authentication#gcloud_as_a_docker_credential_helper for images hosted on the Google Cloud Registry

## Usage

Add `mina-kubernetes` to your local Gemfile.

Create a configuration file for mina in `config/deploy.rb` like the one below:
```ruby
require "mina/default"
require "mina/multistage"
require "mina/kubernetes"

task :deploy do
  invoke :"kubernetes:deploy"
end
```

Add the following variables to your stage configuration i.e. `config/deploy/production.rb`:
```ruby
set :namespace, "my_app"
set :image_repo, "gcr.io/project-id/myapp"
set :kubernetes_context, "kubernetes_context_name"
```

If `set :image_tag, "my_image_tag"` is also defined, it'll be used to deploy the image tagged with this tag on the repository. Otherwise you'll be prompted to pick a branch from current working Git repository and the image to deploy will be assumed to be tagged with the Git commit hash, i.e. `gcr.io/project-123456/my_app:abcd1234`.

Then add `*.yml.erb` Kubernetes resource definition files in the stage folder, i.e. `config/deploy/production/app.yml.erb`. Occurences of `<%= image_repo %>` and `<%= current_sha %>` in these files will be dynamically replaced on deploy by the image repository URL and the latest commit hash of the selected branch on its git origin.

You can also get the RAILS_MASTER_KEY for encrypted credentials deployed as a Kubernetes secrets by adding a secrets.yml.erb like below:
```yml
apiVersion: v1
kind: Secret
metadata:
  name: secrets
data:
  RAILS_MASTER_KEY: <%= Base64.strict_encode64(File.read("#{Dir.pwd}/config/credentials/production.key").strip) %>
```

When running `mina production deploy`, it'll prompt for a branch and check the image tagged with current commit hash from selected branch is available on the repository. Then the `kubernetes-deploy` executable is called to fill in the variables in the resource templates and apply them all to the cluster under the given namespace (see https://github.com/Shopify/kubernetes-deploy#deploy-walkthrough for more details)

### Passing options to kubernetes-deploy

```ruby
  invoke :"kubernetes:deploy", "--no-prune"
```

Refer to https://github.com/Shopify/krane#usage for a complete set of options

### Tasks available

#### `kubernetes:deploy`

Creates namespace on cluster and assigns it to a local kubectl context, prompts for git branch if no image tag specified, applies all resources to cluster after checking tagged image is available.

#### `kubernetes:bash`

Prompts for branch unless image tag is set, then spins up a temporary pod with the image and opens up a remote bash terminal.

#### `kubernetes:command`

Prompts for branch unless image tag is set, then spins up a temporary pod with the image and run command given by task variable `command`, for instance with `set :command, "rails console"`. Environment variables can also be given by defining`env_hash`, i.e. `set :env_hash, {"RAILS_ENV" => "production", "MY_VAR" => "abcd123"}`

#### `kubernetes:delete`

Confirms and delete all resources on cluster under namespace.
