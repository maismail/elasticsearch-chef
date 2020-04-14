include_recipe "java"

node.override['elasticsearch']['version'] = node['elastic']['version']
node.override['elasticsearch']['download_urls']['tarball'] = node['elastic']['url']

Chef::Log.info "Using systemd (1): #{node['elastic']['systemd']}"

#service_name = "elasticsearch-#{node['elastic']['node_name']}"
service_name = "elasticsearch"
pid_file = "/tmp/elasticsearch.pid"

case node['platform_family']
when 'rhel'
  package 'unzip'
end

group node['elastic']['group'] do
  action :create
  not_if "getent group #{node['elastic']['group']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

user node['elastic']['user'] do
  gid node['elastic']['group']
  shell "/bin/bash"
  manage_home false
  system true
  action :create
  not_if "getent passwd #{node['elastic']['user']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node['kagent']['certs_group'] do
  action :modify
  members ["#{node["elastic"]["user"]}"]
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

elasticsearch_user 'elasticsearch' do
  username node['elastic']['user']
  groupname node['elastic']['group']
  shell '/bin/bash'
  comment 'Elasticsearch User'
  instance_name node['elastic']['node_name']
  action :nothing
end

install_dir = Hash.new
install_dir['package'] = node['elastic']['dir']
install_dir['tarball'] = node['elastic']['dir']

node.override['ark']['prefix_root'] = node['elastic']['dir']
node.override['ark']['prefix_bin'] = node['elastic']['dir']
node.override['ark']['prefix_home'] = node['elastic']['dir']

elasticsearch_install 'elasticsearch' do
  type "tarball"
  version node['elastic']['version']
  instance_name node['elastic']['node_name']
  download_url node['elasticsearch']['download_urls']['tarball']
  download_checksum node['elastic']['checksum']
  dir node['elastic']['dir']
  action :install
end

node.override['ulimit']['conf_dir'] = "/etc/security"
node.override['ulimit']['conf_file'] = "limits.conf"

node.override['ulimit']['params']['default']['nofile'] = 65000     # hard and soft open file limit for all users
node.override['ulimit']['params']['default']['nproc'] = 8000

node.override['ulimit']['conf_dir'] = "/etc/security"
node.override['ulimit']['conf_file'] = "limits.conf"

node.override['ulimit']['params']['default']['nofile'] = 65000     # hard and soft open file limit for all users
node.override['ulimit']['params']['default']['nproc'] = 8000

include_recipe "ulimit2"

node.override['elasticsearch']['url'] = node['elastic']['url']
node.override['elasticsearch']['version'] = node['elastic']['version']

directory "#{node['elastic']['bin_dir']}/consul" do
  owner node['elastic']['user']
  group node['elastic']['group']
  mode "0750"
  action :create
end

template "#{node['elastic']['bin_dir']}/consul/elasticsearch-health.sh" do
  source "consul/elasticsearch-health.sh.erb"
  owner node['elastic']['user']
  group node['elastic']['group']
  mode 0750
  variables({
    :elastic_url => my_elastic_url()
  })
end

consul_service "Registering Elasticsearch with Consul" do
  service_definition "consul/elasticsearch-consul.hcl.erb"
  template_variables({
    :id => my_elastic_node_id()
  })
  action :register
end

elastic_fqn = consul_helper.get_service_fqdn("elasticsearch")
Chef::Log.error "Test Elasticsearch with Consul #{elastic_fqn}"

all_elastic_hosts = all_elastic_host_names()
elastic_host = my_host()
elasticsearch_configure 'elasticsearch' do
   path_home node['elastic']['home_dir']
   path_conf node['elastic']['config_dir']
   path_data node['elastic']['data_dir']
   path_logs node['elastic']['log_dir']
   path_plugins node['elastic']['plugins_dir']
   path_bin node['elastic']['bin_dir']
   logging({:"action" => 'INFO'})
   configuration ({
     'cluster.name' => node['elastic']['cluster_name'],
     'node.name' => elastic_host,
     'node.master' => node['elastic']['master'].casecmp?("true") ,
     'node.data' => node['elastic']['data'].casecmp?("true"),
     'network.host' =>  elastic_host,
     'transport.port' => node['elastic']['ntn_port'],
     'http.port' => node['elastic']['port'],
     'http.cors.enabled' => true,
     'http.cors.allow-origin' => "*",
     'discovery.seed_hosts' => all_elastic_hosts,
     'cluster.initial_master_nodes' => all_elastic_hosts,
     'cluster.max_shards_per_node' => node['elastic']['cluster']['max_shards_per_node'],
     'opendistro_security.allow_unsafe_democertificates' => false,
     'opendistro_security.disabled' => node['elastic']['opendistro_security']['enabled'].casecmp?("false"),
     'opendistro_security.ssl.transport.enabled' => true,
     'opendistro_security.ssl.transport.keystore_type' => node['elastic']['opendistro_security']['keystore']['type'],
     'opendistro_security.ssl.transport.keystore_filepath' => node['elastic']['opendistro_security']['keystore']['file'],
     'opendistro_security.ssl.transport.keystore_password' =>  node['elastic']['opendistro_security']['keystore']['password'],
     'opendistro_security.ssl.transport.truststore_type' => node['elastic']['opendistro_security']['truststore']['type'],
     'opendistro_security.ssl.transport.truststore_filepath' => node['elastic']['opendistro_security']['truststore']['file'],
     'opendistro_security.ssl.transport.truststore_password' => node['elastic']['opendistro_security']['truststore']['password'],
     'opendistro_security.ssl.http.enabled' => node['elastic']['opendistro_security']['https']['enabled'].casecmp?("true"),
     'opendistro_security.ssl.http.keystore_type' => node['elastic']['opendistro_security']['keystore']['type'],
     'opendistro_security.ssl.http.keystore_filepath' => node['elastic']['opendistro_security']['keystore']['file'],
     'opendistro_security.ssl.http.keystore_password' => node['elastic']['opendistro_security']['keystore']['password'],
     'opendistro_security.ssl.http.truststore_type' => node['elastic']['opendistro_security']['truststore']['type'],
     'opendistro_security.ssl.http.truststore_filepath' => node['elastic']['opendistro_security']['truststore']['file'],
     'opendistro_security.ssl.http.truststore_password' =>  node['elastic']['opendistro_security']['truststore']['password'],
     'opendistro_security.allow_default_init_securityindex' => true,
     'opendistro_security.restapi.roles_enabled' => ["all_access", "security_rest_api_access"],
     'opendistro_security.roles_mapping_resolution' => 'BOTH',
     'opendistro_security.nodes_dn' => all_elastic_nodes_dns(),
     'opendistro_security.authcz.admin_dn' => get_elastic_admin_dn(),
     'opendistro_security.audit.enable_rest' => node['elastic']['opendistro_security']['audit']['enable_rest'].casecmp?("true"),
     'opendistro_security.audit.enable_transport' => node['elastic']['opendistro_security']['audit']['enable_transport'].casecmp?("true"),
     'opendistro_security.audit.type' => node['elastic']['opendistro_security']['audit']['type'],
     'opendistro_security.audit.threadpool.size' => node['elastic']['opendistro_security']['audit']['threadpool']['size'],
     'opendistro_security.audit.threadpool.max_queue_len' => node['elastic']['opendistro_security']['audit']['threadpool']['max_queue_len']
   })
   instance_name elastic_host
   action :manage
end

directory node['elastic']['data_dir'] do
  owner node['elastic']['user']
  group node['elastic']['group']
  mode '0700'
  recursive true
end

hopsworks_alt_url = "https://#{private_recipe_ip("hopsworks","default")}:8181"
if node.attribute? "hopsworks"
  if node["hopsworks"].attribute? "https" and node["hopsworks"]['https'].attribute? ('port')
    hopsworks_alt_url = "https://#{private_recipe_ip("hopsworks","default")}:#{node['hopsworks']['https']['port']}"
  end
end

elastic_opendistro 'opendistro_security' do
  hopsworks_alt_url hopsworks_alt_url
  action :install_security
end

template "#{node['elastic']['opendistro_security']['config_dir']}/action_groups.yml" do
  source "action_groups.yml.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "600"
end

template "#{node['elastic']['opendistro_security']['config_dir']}/internal_users.yml" do
  source "internal_users.yml.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "600"
end

template "#{node['elastic']['opendistro_security']['config_dir']}/roles.yml" do
  source "roles.yml.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "600"
end

template "#{node['elastic']['opendistro_security']['config_dir']}/roles_mapping.yml" do
  source "roles_mapping.yml.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "600"
end

template "#{node['elastic']['opendistro_security']['config_dir']}/tenants.yml" do
  source "tenants.yml.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "600"
end

template "#{node['elastic']['opendistro_security']['tools_dir']}/run_securityAdmin.sh" do
  source "run_securityAdmin.sh.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "700"
end

signing_key = ""
if node['elastic']['opendistro_security']['jwt']['enabled'].casecmp?("true") 
  signing_key = get_elk_signing_key()
end 

template "#{node['elastic']['opendistro_security']['config_dir']}/config.yml" do
  source "config.yml.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "600"
  variables({
    :signing_key => signing_key,
  })
end

elasticsearch_service "#{service_name}" do
   instance_name node['elastic']['node_name']
   init_source 'elasticsearch.erb'
   init_cookbook 'elastic'
   service_actions ['nothing']
end

template "#{node['elastic']['home_dir']}/config/jvm.options" do
  source "jvm.options.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "755"
end

template "#{node['elastic']['home_dir']}/bin/elasticsearch-start.sh" do
  source "elasticsearch-start.sh.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "751"
end

template "#{node['elastic']['home_dir']}/bin/elasticsearch-stop.sh" do
  source "elasticsearch-stop.sh.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "751"
end

template "#{node['elastic']['home_dir']}/bin/kill-process.sh" do
  source "kill-process.sh.erb"
  user node['elastic']['user']
  group node['elastic']['group']
  mode "751"
end


if node['kagent']['enabled'] == "true"
# Note, the service below cannot have a '-' in its name, so we call it just
# "elasticsearch". The service_name will be the name of the init.d/systemd script.
  kagent_config service_name do
    service "ELK"
    log_file "#{node['elastic']['home_dir']}/logs/#{node['elastic']['cluster_name']}.log"
  end
end

file "/etc/init.d/#{service_name}" do
   action :delete
end

file "/etc/defaults/#{service_name}" do
   action :delete
end

file "/etc/rc.d/init.d/#{service_name}" do
  action :delete
end

elastic_service = "/lib/systemd/system/#{service_name}.service"

case node['platform_family']
when "rhel"
  elastic_service =  "/usr/lib/systemd/system/#{service_name}.service"
end

execute "systemctl daemon-reload"

template "#{elastic_service}" do
  source "elasticsearch.service.erb"
  user "root"
  group "root"
  mode "754"
  variables({
              :start_script => "#{node['elastic']['home_dir']}/bin/elasticsearch-start.sh",
              :stop_script => "#{node['elastic']['home_dir']}/bin/elasticsearch-stop.sh",
              :install_dir => "#{node['elastic']['home_dir']}",
              :pid => pid_file,
              :nofile_limit => node['elastic']['limits']['nofile'],
              :memlock_limit => node['elastic']['limits']['memory_limit']
            })
#    notifies :enable, "service[#{service_name}]"
#    notifies :restart, "service[#{service_name}]", :immediately
end

Chef::Log.info "Using systemd (2): #{node['elastic']['systemd']}"

service "#{service_name}" do
  case node['elastic']['systemd']
  when "true"
  provider Chef::Provider::Service::Systemd
  else
  provider Chef::Provider::Service::Init::Debian
  end
  supports :restart => true, :stop => true, :start => true, :status => true
  if node['services']['enabled'] == "true"
    action :enable
  end
end


elastic_start "start_install_elastic" do
  elastic_url my_elastic_url()
  if opendistro_security?()
    user node['elastic']['opendistro_security']['admin']['username']
    password node['elastic']['opendistro_security']['admin']['password']
  end
  action :run
end

# Download exporter
base_package_filename = File.basename(node['elastic']['exporter']['url'])
cached_package_filename = "#{Chef::Config['file_cache_path']}/#{base_package_filename}"

remote_file cached_package_filename do
  source node['elastic']['exporter']['url']
  owner "root"
  mode "0644"
  action :create_if_missing
end

elastic_exporter_downloaded= "#{node['elastic']['exporter']['home']}/.elastic_exporter.extracted_#{node['elastic']['exporter']['version']}"
# Extract elastic_exporter 
bash 'extract_elastic_exporter' do
  user "root"
  code <<-EOH
    set -e
    tar -xf #{cached_package_filename} -C #{node['elastic']['dir']}
    chown -R #{node['elastic']['user']}:#{node['elastic']['group']} #{node['elastic']['exporter']['home']}
    chmod -R 750 #{node['elastic']['exporter']['home']}
    touch #{elastic_exporter_downloaded}
    chown #{node['elastic']['user']} #{elastic_exporter_downloaded}
  EOH
  not_if { ::File.exists?( elastic_exporter_downloaded ) }
end

link node['elastic']['exporter']['base_dir'] do
  owner node['elastic']['user']
  group node['elastic']['group']
  to node['elastic']['exporter']['home']
end

# Template and configure elasticsearch exporter 
case node['platform_family']
when "rhel"
  systemd_script = "/usr/lib/systemd/system/elastic_exporter.service" 
else
  systemd_script = "/lib/systemd/system/elastic_exporter.service"
end

service "elastic_exporter" do
  provider Chef::Provider::Service::Systemd
  supports :restart => true, :stop => true, :start => true, :status => true
  action :nothing
end

deps = "elasticsearch.service"

template systemd_script do
  source "elastic_exporter.service.erb"
  owner "root"
  group "root"
  mode 0664
  variables({
              :deps => deps
            })
  if node['services']['enabled'] == "true"
    notifies :enable, "service[elastic_exporter]", :immediately
  end
  notifies :restart, "service[elastic_exporter]", :immediately
  variables({
    'es_master_uri' => get_my_es_master_uri()
  })
end

kagent_config "elastic_exporter" do
  action :systemd_reload
end

if node['kagent']['enabled'] == "true"
   kagent_config "elastic_exporter" do
     service "Monitoring"
     restart_agent false
   end
end

if conda_helpers.is_upgrade
  kagent_config "#{service_name}" do
    action :systemd_reload
  end

  kagent_config "elastic_exporter" do
    action :systemd_reload
  end
end
