require "tty-prompt"
require "tty-spinner"
require "securerandom"
require "json"
require "base64"

# required by mina
set :execution_mode, :pretty

# default for kubernetes-deploy
set :kube_config, "~/.kube/config"

namespace :kubernetes do

  set :namespace, fetch(:app_name)
  set :context, "#{fetch(:namespace)}-#{fetch(:stage)}"

  task :deploy do
    desc "Set image tag to be latest commit of prompted branch (unless provided) then applies resources to cluster"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag))
    create_namespace_on_cluster
    set_local_config_context
    apply_kubernetes_resources
  end

  task :bash do
    desc "Spins up temporary pod with image and opens remote interactive bash"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag))
    run_terminal_command("bash")
  end

  task :command do
    desc "Spins up temporary pod with image and runs given command in interactive shell, passing given environment variable"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag))
    run_terminal_command(fetch(:command), fetch(:env_hash))
  end

  task :delete do
    desc "Delete all resources in namespace on cluster"
    if TTY::Prompt.new.yes?("This will delete all resources in namespace #{fetch(:namespace)} on cluster #{fetch(:kubernetes_cluster)}, are you sure?")
      run :local do
        comment "Deleting all resources in #{fetch(:namespace)}..."
        command "kubectl delete namespace #{fetch(:namespace)} --cluster=#{fetch(:kubernetes_cluster)}"
        comment "Removing local config context..."
        command "kubectl config unset contexts.#{fetch(:context)}"
      end
    end
  end

end

private

def set_tag_from_branch_commit
  run :local do
    comment "Updating Git branches..."
  end
  remote_branches = `git fetch --prune && git branch -r --no-merged master --sort=-committerdate | grep origin`.split("\n").collect { |b| b.strip.gsub("origin/", "") }.reject { |b| b == "master" }
  set :branch, TTY::Prompt.new.select("Which branch?", ["master"].concat(remote_branches))
  set :image_tag, `git rev-parse origin/#{fetch(:branch)}`.split("\n")[0]
end

def create_namespace_on_cluster
  run :local do
    comment "Create/update namespace on Kubernetes cluster..."
    command "kubectl create namespace #{fetch(:namespace)} --dry-run -o yaml | kubectl apply -f - --cluster=#{fetch(:kubernetes_cluster)}"
  end
end

def set_local_config_context
  run :local do
    comment "Set up local Kubernetes config context..."
    command "kubectl config set-context #{fetch(:context)} --namespace=#{fetch(:namespace)} --cluster=#{fetch(:kubernetes_cluster)} --user=#{fetch(:kubernetes_user)}"
  end
end

def wait_until_image_ready(commit)
  run :local do
    comment "Check image #{fetch(:image_repo)}:#{commit} is available..."
  end
  spinner = TTY::Spinner.new
  spinner.auto_spin
  while !image_available?(commit)
    sleep 5
  end
  spinner.stop
end

def image_available?(commit)
  system("docker manifest inspect #{fetch(:image_repo)}:#{commit} > /dev/null") == true
end

def run_terminal_command(command, env_hash = {})
  env = env_hash.collect{|k,v| "--env #{k}=#{v}" }.join(" ")
  label = command.downcase.gsub(" ", "-").gsub(":", "-")
  # using system instead of mina's command so tty opens successfully
  system "kubectl run #{label}-#{SecureRandom.hex(4)} --rm -i --tty --restart=Never --context=#{fetch(:context)} --image #{fetch(:image_repo)}:#{fetch(:image_tag)} #{env} -- #{command}"
end

def apply_kubernetes_resources
  run :local do
    comment "Apply all Kubernetes resources..."
    command "REVISION=#{fetch(:image_tag)} KUBECONFIG=#{fetch(:kube_config)} ENVIRONMENT=#{fetch(:stage)} kubernetes-deploy --bindings=image_repo=#{fetch(:image_repo)},image_tag=#{fetch(:image_tag)},namespace=#{fetch(:namespace)} #{fetch(:namespace)} #{fetch(:context)}"
  end
end