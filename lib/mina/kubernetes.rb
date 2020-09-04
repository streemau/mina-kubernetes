require "tty-prompt"
require "tty-spinner"
require "securerandom"
require "json"
require "base64"

# required by mina
set :execution_mode, :pretty

namespace :kubernetes do
  set :proxy, nil

  task :deploy, [:options] do |task, args|
    desc "Set image tag to be latest commit of prompted branch (unless provided) then applies resources to cluster"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag))
    create_namespace_on_cluster
    apply_kubernetes_resources(args[:options])
  end

  task :bash do
    desc "Spins up temporary pod with image and opens remote interactive bash"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag))
    run_command("bash")
  end

  task :command do
    desc "Spins up temporary pod with image and runs given command in interactive shell, passing given environment variable"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag))
    run_command(fetch(:command), env_hash_arg, :overrides_hash => fetch(:overrides))
  end

  task :delete do
    desc "Delete all resources in namespace on cluster"
    if TTY::Prompt.new.yes?("This will delete all resources in namespace #{fetch(:namespace)} on context #{fetch(:kubernetes_context)}, are you sure?")
      run :local do
        comment "Deleting all resources in #{fetch(:namespace)}..."
        command "kubectl delete namespace #{fetch(:namespace)} --context=#{fetch(:kubernetes_context)}"
      end
    end
  end

end

private

def env_hash_arg
  @env_hash_arg ||= (fetch(:env_hash).is_a?(String) ? JSON.parse(fetch(:env_hash)) : fetch(:env_hash)) || {}
end

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
    proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)
    command "kubectl create namespace #{fetch(:namespace)} --dry-run -o yaml | #{proxy_env} kubectl apply -f - --context=#{fetch(:kubernetes_context)}"
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

def run_command(command, env_hash = {}, overrides_hash: nil)
  env = env_hash.collect{|k,v| "--env #{k}=#{v}" }.join(" ")
  overrides = "--overrides=#{overrides_hash.to_json}" if overrides_hash
  label = command.downcase.gsub(" ", "-").gsub(":", "-")
  proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)

  # using system instead of mina's command so tty opens successfully
  system "#{proxy_env} kubectl run #{label}-#{SecureRandom.hex(4)} --rm -i --tty --restart=Never --context=#{fetch(:kubernetes_context)} --namespace=#{fetch(:namespace)} --image #{fetch(:image_repo)}:#{fetch(:image_tag)} #{env} #{overrides} -- #{command}"
end

def apply_kubernetes_resources(options)
  run :local do
    comment "Apply all Kubernetes resources..."

    proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)
    filepaths = options&.[](:filepaths) || "config/deploy/#{fetch(:stage)}"

    render_cmd = "#{proxy_env} krane render --bindings=image_repo=#{fetch(:image_repo)},image_tag=#{fetch(:image_tag)},namespace=#{fetch(:namespace)} --current_sha #{fetch(:image_tag)} -f #{filepaths}"
    deploy_cmd = "#{proxy_env} krane deploy #{fetch(:namespace)} #{fetch(:kubernetes_context)} --stdin "
    deploy_cmd += options[:deployment_options] if options&.[](:deployment_options)

    ejson_secrets_path = "#{filepaths}/secrets.ejson"
    deploy_cmd += " --filenames #{ejson_secrets_path}" if File.exists?(ejson_secrets_path)

    command "#{render_cmd} | #{deploy_cmd}"
  end
end
