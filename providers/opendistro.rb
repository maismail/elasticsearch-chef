action :install_security do
  bash "install_opendistro_security_plugin" do
    user node['elastic']['user']
    code <<-EOF
    #{node['elastic']['bin_dir']}/elasticsearch-plugin install --batch #{node['elastic']['opendistro_security']['url']}
    chmod +x #{node['elastic']['opendistro_security']['tools_dir']}/*
    EOF
  end

  link node['elastic']['opendistro_security']['keystore']['location'] do
    owner node['elastic']['user']
    group node['elastic']['group']
    to node['elastic']['kagent']['keystore']['location']
  end

  link node['elastic']['opendistro_security']['truststore']['location'] do
    owner node['elastic']['user']
    group node['elastic']['group']
    to node['elastic']['kagent']['truststore']['location']
  end
end


action :run_securityadmin do
  bash "opendistro_security_run_securityadmin" do
    user node['elastic']['user']
    code <<-EOF
    #{node['elastic']['opendistro_security']['tools']['securityadmin']} -cd #{node['elastic']['opendistro_security']['config_dir']} -icl -nhnv -h #{node['fqdn']} -ts #{node['elastic']['opendistro_security']['truststore']['location']} -tspass #{node['elastic']['opendistro_security']['truststore']['password']} -ks #{node['elastic']['opendistro_security']['keystore']['location']} -kspass #{node['elastic']['opendistro_security']['keystore']['password']}
    EOF
  end
end
