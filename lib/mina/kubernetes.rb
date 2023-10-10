require "tty-prompt"
require "tty-spinner"
require "json"
require "time"

# required by mina
set :execution_mode, :pretty

namespace :kubernetes do
  set :proxy, nil
  set :skip_image_ready_check, false

  task :deploy, [:options] do |task, args|
    desc "Set image tag to be latest commit of prompted branch (unless provided) then applies resources to cluster"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag)) unless fetch(:skip_image_ready_check)
    create_namespace_on_cluster
    apply_kubernetes_resources(args[:options])
  end

  task :global_deploy, [:options] do |task, args|
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag)) unless fetch(:skip_image_ready_check)
    apply_global_kubernetes_resources(args[:options])
  end

  task :bash do
    desc "Spins up temporary pod with image and opens remote interactive bash"
    set_tag_from_branch_commit unless fetch(:image_tag)
    wait_until_image_ready(fetch(:image_tag)) unless fetch(:skip_image_ready_check)
    run_command("bash")
  end

  task :command do
    set :skip_report_time, true
    desc "Spins up temporary pod with image and runs given command in interactive shell, passing given environment variable"
    set_tag_from_branch_commit unless fetch(:image_tag)
    run_command(fetch(:command), env_hash_arg)
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
    comment "Refreshing Git branches..."
  end
  remote_branches = `git fetch --prune && git branch -r --no-merged master --sort=-committerdate | grep origin`.split("\n").collect { |b| b.strip.gsub("origin/", "") }.reject { |b| b == "master" }
  set :branch, TTY::Prompt.new.select("Which branch?", ["master"].concat(remote_branches))
  set :image_tag, `git rev-parse origin/#{fetch(:branch)}`.split("\n")[0]
end

def create_namespace_on_cluster
  run :local do
    comment "Create/update namespace on Kubernetes cluster..."
    proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)
    command "kubectl create namespace #{fetch(:namespace)} --dry-run=client -o yaml | #{proxy_env} kubectl apply -f - --context=#{fetch(:kubernetes_context)}"
  end
end

def wait_until_image_ready(commit)
  run :local do
    comment "Checking image #{fetch(:image_repo)}:#{commit} is available..."
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

def run_command(command, env_hash = {})
  env = env_hash.collect{|k,v| "--env #{k}=#{v}" }.join(" ")
  proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)

  default_pod_name = "#{`whoami`.strip}-#{command}-#{fetch(:branch)}".downcase.gsub(" ", "-").gsub(":", "-")
  pod_name = TTY::Prompt.new.ask("What name for the pod?", :value => default_pod_name)

  run :local do
    comment "Lauching pod #{color(pod_name, 36)} to run #{color(command, 36)}"
  end

  pod_run_command = "#{proxy_env} kubectl run #{pod_name} --rm -i --tty --restart=Never --overrides='#{fetch(:kubectl_pod_overrides)}' --context=#{fetch(:kubernetes_context)} --namespace=#{fetch(:namespace)} --image #{fetch(:image_repo)}:#{fetch(:image_tag)} #{env}"
  running_pod_info = `#{proxy_env} kubectl get pod #{pod_name} -o json --ignore-not-found --context=#{fetch(:kubernetes_context)} --namespace=#{fetch(:namespace)}`

  if running_pod_info.empty?
    wait_for_image_and_run_command("#{pod_run_command} -- #{command}")
  else
    started_at = Time.parse(JSON.parse(running_pod_info)["status"]["startTime"]).strftime('%b %e, %H:%M')
    choice = TTY::Prompt.new.select(
      "Pod already exists, running since #{started_at} UTC, what would you like to do?",
      {
        "Reattach to its container" => :attach,
        "Kill it and launch a fresh one" => :replace,
        "Keep it and start one with a different name" => :other,
      }
    )
    
    delete_command = "#{proxy_env} kubectl delete pod #{pod_name} --context=#{fetch(:kubernetes_context)} --namespace=#{fetch(:namespace)}"
    
    case choice
    when :attach
      attach_command = "#{proxy_env} kubectl attach #{pod_name} -i --tty -c #{pod_name} --context=#{fetch(:kubernetes_context)} --namespace=#{fetch(:namespace)}"
      system "#{attach_command} && #{delete_command}"
    when :replace
      system delete_command
      run :local do
        comment "Launching Pod #{color(pod_name, 36)} to run #{color(command, 36)}"
      end
      wait_for_image_and_run_command("#{pod_run_command} -- #{command}")
    when :other
      run_command(command, env_hash)
    end
  end
end

def wait_for_image_and_run_command(command)
  wait_until_image_ready(fetch(:image_tag))
  system command
end

def apply_kubernetes_resources(options)
  run :local do
    comment "Applying all Kubernetes resources..."

    proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)
    filepaths = options&.[](:filepaths) || "config/deploy/#{fetch(:stage)}"

    render_cmd = "#{proxy_env} krane render --bindings=image_repo=#{fetch(:image_repo)},image_tag=#{fetch(:image_tag)},namespace=#{fetch(:namespace)} --current_sha #{fetch(:image_tag)} -f #{filepaths}"
    deploy_cmd = "#{proxy_env} krane deploy #{fetch(:namespace)} #{fetch(:kubernetes_context)} --stdin "
    deploy_cmd += options[:deployment_options] if options&.[](:deployment_options)

    ejson_secrets_path = "#{filepaths}/secrets.ejson"
    deploy_cmd += " --filenames #{ejson_secrets_path}" if File.exist?(ejson_secrets_path)

    command "#{render_cmd} | #{deploy_cmd}"
  end
end

def apply_global_kubernetes_resources(options)
  run :local do
    comment "Applying all global Kubernetes resources..."

    proxy_env = "HTTPS_PROXY=#{fetch(:proxy)}" if fetch(:proxy)
    filepaths = options&.[](:filepaths) || "config/deploy/#{fetch(:stage)}"

    render_cmd = "#{proxy_env} krane render --bindings=image_repo=#{fetch(:image_repo)},image_tag=#{fetch(:image_tag)},nzamespace=#{fetch(:namespace)} --current_sha #{fetch(:image_tag)} -f #{filepaths}"
    deploy_cmd = "#{proxy_env} krane global-deploy #{fetch(:kubernetes_context)} --selector #{fetch(:global_deploy_selector_key)}=#{fetch(:global_deploy_selector_value)} --stdin "
    deploy_cmd += options[:deployment_options] if options&.[](:deployment_options)

    ejson_secrets_path = "#{filepaths}/secrets.ejson"
    deploy_cmd += " --filenames #{ejson_secrets_path}" if File.exist?(ejson_secrets_path)

    command "#{render_cmd} | #{deploy_cmd}"
  end
end
