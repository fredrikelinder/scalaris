#
# Cookbook Name:: scalaris_PIC
# Attributes:: default
#
# Copyright 2012, Zuse Institute Berlin
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

default[:REC][:PICs][:scalaris_PIC] = [
  {:attributes => {
                    :scalaris_port => 14195,
                    :scalaris_port_web => 8000,
                    :scalaris_node => "node@#{node['ipaddress']}",
                    :scalaris_start_first => true,
                    :scalaris_start_mgmt_server => true,
                    :scalaris_mgmt_server => {"ip4" => "#{node['ipaddress']}", "port" => 14195},
                    :scalaris_known_hosts => [{"ip4" => "#{node['ipaddress']}", "port" => 14195}], # update on deployment to known IP of another node
                    :scalaris_nodes_per_vm => 1,
                    :scalaris_max_json_req_size => 1024*1024,
                    :scalaris_users => [] # [{"user" => "User", "password" => "Password"}], if empty => no restrictions
                   }
  }]

#puts "Printing scalaris attributes from attributes file: #{node[:REC][:PICs][:scalaris_PIC][0][:attributes]} "
