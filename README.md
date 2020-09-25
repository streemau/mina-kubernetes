# mina-kubernetes
 mina-kubernetes is a plugin for the [mina](https://github.com/mina-deploy/mina) deployment tool to streamline deployment of resources to Kubernetes clusters, using the [krane](https://github.com/Shopify/krane) gem with the [mina-multistage](https://github.com/endoze/mina-multistage) plugin.

It requires local Docker and [kubectl](https://cloud.google.com/kubernetes-engine/docs/quickstart) with local authentication set up to connect to the destination Kubernetes cluster as context in your local KUBE_CONFIG. See https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#generate_kubeconfig_entry for example with Google Kubernetes Engine.

NB: `docker manifest inspect` is used to check whether the Docker image with requested tag is available. At the time of writing this is still an experimental feature that needs to be enabled in your local Docker config by adding `"experimental": "enabled"` to `~/.docker/config.json`.
If the image to deploy is in a private repository authentication will have to be set up for your local Docker, for instance see https://cloud.google.com/container-registry/docs/advanced-authentication#gcloud_as_a_docker_credential_helper for images hosted on the Google Cloud Registry.

## Usage

Add `mina-kubernetes` to your local Gemfile.

Create a configuration file for mina in `config/deploy.rb` similar to the one below (which replaces the default deploy task):
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

If `set :image_tag, "my_image_tag"` is also defined, it'll be used to deploy the image tagged with this tag on the repository. Otherwise you'll be prompted to pick a branch from the current Git repository and the image to deploy will be assumed to be tagged with the commit hash of that branch, i.e. `gcr.io/project-id/myapp:abcd1234`.

Then add `*.yml.erb` Kubernetes resource definition files in the stage folder, for instance `config/deploy/production/webserver.yml.erb` and `config/deploy/production/backgroundjobs.yml.erb`. Occurences of `<%= image_repo %>` and `<%= current_sha %>` in these files will be dynamically replaced on deploy by the image repository URL and the latest commit hash of the selected branch on its git origin.

You can also get the RAILS_MASTER_KEY for encrypted credentials deployed as a Kubernetes secrets by adding a secrets.yml.erb like below:
```yml
apiVersion: v1
kind: Secret
metadata:
  name: secrets
data:
  RAILS_MASTER_KEY: <%= Base64.strict_encode64(File.read("#{Dir.pwd}/config/credentials/production.key").strip) %>
```

When running `mina production deploy`, it'll check the image is available on the repository and then call the `krane` executable to fill in the variables in the resource templates and apply them all to the cluster under the given namespace (see https://github.com/Shopify/krane#deploy-walkthrough for more details)

### EJSON Encrypted secrets

Krane can dynamically generate Kubernetes secrets from an encrypted EJSON file, see: https://github.com/Shopify/krane#deploying-kubernetes-secrets-from-ejson. As per current Krane documentation "The ejson file must be included in the resources passed to --filenames, it can not be read through stdin.", so
following convention-over-configuration principles `mina-kubernetes` checks for the presence of a file named `secrets.ejson` in the stage folder and uses it if available.

### Passing custom options to krane

```ruby
  invoke :"kubernetes:deploy", "--no-prune"
```

Refer to https://github.com/Shopify/krane#usage for a complete set of options

## Tasks available

#### `kubernetes:deploy`

Creates the namespace on cluster if it doesn't exist, prompts for a git branch if no image tag is already specified in stage file, then applies all resources to cluster after checking tagged image is available.

#### `kubernetes:bash`

Prompts for branch unless image tag is set, then spins up a temporary pod with the image and opens up a remote bash terminal.

#### `kubernetes:command`

Prompts for branch unless image tag is set, then spins up a temporary pod with the image and runs the command given in the task variable `command`, for instance with `set :command, "rails console"`. Environment variables can also be passed by defining`env_hash`, i.e. `set :env_hash, {"RAILS_ENV" => "production", "MY_VAR" => "abcd123"}`

The pod will be named `command-username-branch`, and can be reattached/killed in case of disconnection.

A `kubectl_pod_overrides` task option is available to pass a value to the `overrides` option of the `kubectl run` command.

#### `kubernetes:delete`

Confirms and delete all resources on cluster under namespace.

## Example use: run rails console on non-preemptible GKE node

Add the following to your `deploy.rb`
``` ruby
task :console do
  set :command, "rails console"
  set :env_hash, "RAILS_ENV" => fetch(:stage), "RAILS_MASTER_KEY" => File.read("#{Dir.pwd}/config/credentials/#{fetch(:stage)}.key").strip
  set :kubectl_pod_overrides, '{"spec": {"affinity": {"nodeAffinity": {"requiredDuringSchedulingIgnoredDuringExecution": {"nodeSelectorTerms": [{"matchExpressions": [{"key": "cloud.google.com/gke-preemptible", "operator": "DoesNotExist"} ] } ] } } } } }'

  invoke :'kubernetes:command'
end
```
You can now run `mina production console` to open a rails console in production environment with the image of your choice!
