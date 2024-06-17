###########################################
#-----------) Cloud functions (-----------#
###########################################

GCP_GOOD_SCOPES="/devstorage.read_only|/logging.write|/monitoring|/servicecontrol|/service.management.readonly|/trace.append"
GCP_BAD_SCOPES="/cloud-platform|/compute"

exec_with_jq(){
  if [ "$(command -v jq)" ]; then 
    $@ | jq 2>/dev/null;
    if ! [ $? -eq 0 ]; then
      $@;
    fi
   else 
    $@;
   fi
}

check_gcp(){
  is_gcp_vm="No"
  is_gcp_function="No"
  if grep -q metadata.google.internal /etc/hosts 2>/dev/null || (curl --connect-timeout 2 metadata.google.internal >/dev/null 2>&1 && [ "$?" -eq "0" ]) || (wget --timeout 2 --tries 1 metadata.google.internal >/dev/null 2>&1 && [ "$?" -eq "0" ]); then
    is_gcp_vm="Yes"
  fi
  # CHeck if /workspace exists
  if [ -d "/workspace" ] && [ -d "/layers" ]; then
    is_gcp_vm="No"
    is_gcp_function="Yes"
  fi
}

check_do(){
  is_do="No"
  if [ -f "/etc/cloud/cloud.cfg.d/90-digitalocean.cfg" ]; then
    is_do="Yes"
  fi
}

check_aliyun_ecs () {
  is_aliyun_ecs="No"
  if [ -f "/etc/cloud/cloud.cfg.d/aliyun_cloud.cfg" ]; then 
    is_aliyun_ecs="Yes"
  fi
}

check_tencent_cvm () {
  is_tencent_cvm="No"
  if grep -qi Tencent /etc/cloud/cloud.cfg; then
      is_tencent_cvm="Yes"
  fi
}

check_ibm_vm(){
  is_ibm_vm="No"
  if grep -q "nameserver 161.26.0.10" "/etc/resolv.conf" && grep -q "nameserver 161.26.0.11" "/etc/resolv.conf"; then
    curl --connect-timeout 2  "http://169.254.169.254" > /dev/null 2>&1 || wget --timeout 2 --tries 1  "http://169.254.169.254" > /dev/null 2>&1
    if [ "$?" -eq 0 ]; then
      IBM_TOKEN=$( ( curl -s -X PUT "http://169.254.169.254/instance_identity/v1/token?version=2022-03-01" -H "Metadata-Flavor: ibm" -H "Accept: application/json" 2> /dev/null | cut -d '"' -f4 ) || ( wget --tries 1 -O - --method PUT "http://169.254.169.254/instance_identity/v1/token?version=2022-03-01" --header "Metadata-Flavor: ibm" --header "Accept: application/json" 2>/dev/null | cut -d '"' -f4 ) )
      is_ibm_vm="Yes"
    fi
  fi
}

check_aws_ecs(){
  is_aws_ecs="No"
  if (env | grep -q ECS_CONTAINER_METADATA_URI_v4); then
    is_aws_ecs="Yes";
    aws_ecs_metadata_uri=$ECS_CONTAINER_METADATA_URI_v4;
    aws_ecs_service_account_uri="http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
  
  elif (env | grep -q ECS_CONTAINER_METADATA_URI); then
    is_aws_ecs="Yes";
    aws_ecs_metadata_uri=$ECS_CONTAINER_METADATA_URI;
    aws_ecs_service_account_uri="http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
  
  elif (env | grep -q AWS_CONTAINER_CREDENTIALS_RELATIVE_URI); then
    is_aws_ecs="Yes";
  fi
  
  if [ "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
    aws_ecs_service_account_uri="http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
  fi
}

check_aws_ec2(){
  is_aws_ec2="No"
  is_aws_ec2_beanstalk="No"

  if [ -d "/var/log/amazon/" ]; then
    is_aws_ec2="Yes"
    EC2_TOKEN=$(curl --connect-timeout 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || wget --timeout 2 --tries 1 -q -O - --method PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)

  else
    EC2_TOKEN=$(curl --connect-timeout 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || wget --timeout 2 --tries 1 -q -O - --method PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
    if [ "$(echo $EC2_TOKEN | cut -c1-2)" = "AQ" ]; then
      is_aws_ec2="Yes"
    fi
  fi
  
  if [ "$is_aws_ec2" = "Yes" ] && grep -iq "Beanstalk" "/etc/motd"; then
    is_aws_ec2_beanstalk="Yes"
  fi
}

check_aws_lambda(){
  is_aws_lambda="No"

  if (env | grep -q AWS_LAMBDA_); then
    is_aws_lambda="Yes"
  fi
}

check_aws_codebuild(){
  is_aws_codebuild="No"

  if [ -f "/codebuild/output/tmp/env.sh" ] && grep -q "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" "/codebuild/output/tmp/env.sh" ; then
    is_aws_codebuild="Yes"
  fi
}

check_az_vm(){
  is_az_vm="No"

  if [ -d "/var/log/azure/" ]; then
    is_az_vm="Yes"
  
  elif cat /etc/resolv.conf 2>/dev/null | grep -q "search reddog.microsoft.com"; then
    is_az_vm="Yes"
  fi
}

check_az_app(){
  is_az_app="No"

  if [ -d "/opt/microsoft" ] && env | grep -q "IDENTITY_ENDPOINT"; then
    is_az_app="Yes"
  fi
}


check_gcp
print_list "GCP Virtual Machine? ................. $is_gcp_vm\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
print_list "GCP Cloud Funtion? ................... $is_gcp_function\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_aws_ecs
print_list "AWS ECS? ............................. $is_aws_ecs\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_aws_ec2
print_list "AWS EC2? ............................. $is_aws_ec2\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
print_list "AWS EC2 Beanstalk? ................... $is_aws_ec2_beanstalk\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_aws_lambda
print_list "AWS Lambda? .......................... $is_aws_lambda\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_aws_codebuild
print_list "AWS Codebuild? ....................... $is_aws_codebuild\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_do
print_list "DO Droplet? .......................... $is_do\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_aliyun_ecs
print_list "Aliyun ECS? .......................... $is_aliyun_ecs\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_tencent_cvm
print_list "Tencent CVM? .......................... $is_tencent_cvm\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_ibm_vm
print_list "IBM Cloud VM? ........................ $is_ibm_vm\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_az_vm
print_list "Azure VM? ............................ $is_az_vm\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"
check_az_app
print_list "Azure APP? ........................... $is_az_app\n"$NC | sed "s,Yes,${SED_RED}," | sed "s,No,${SED_GREEN},"

echo ""

if [ "$is_tencent_cvm" = "Yes" ]; then
  tencent_req=""
  if [ "$(command -v curl)" ]; then 
    tencent_req='curl --connect-timeout 2 -sfkG'
  elif [ "$(command -v wget)" ]; then
    tencent_req='wget -q --timeout 2 --tries 1  -O -'
  else 
    echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
  fi

  
    print_2title "Tencent CVM Enumeration"
    print_info "https://cloud.tencent.com/document/product/213/4934"
    # Todo: print_info "Hacktricks Documents needs to be updated"

    echo ""
    print_3title "Instance Info"
    i_tencent_owner_account=$(eval $tencent_req http://169.254.0.23/latest/meta-data/app-id)
    [ "$i_tencent_owner_account" ] && echo "Tencent Owner Account: $i_tencent_owner_account"
    i_hostname=$(eval $tencent_req http://169.254.0.23/latest/meta-data/hostname)
    [ "$i_hostname" ] && echo "Hostname: $i_hostname"
    i_instance_id=$(eval $tencent_req http://169.254.0.23/latest/meta-data/instance-id)
    [ "$i_instance_id" ] && echo "Instance ID: $i_instance_id"
    i_instance_id=$(eval $tencent_req http://169.254.0.23/latest/meta-data/uuid)
    [ "$i_instance_id" ] && echo "Instance ID: $i_instance_id"
    i_instance_name=$(eval $tencent_req http://169.254.0.23/latest/meta-data/instance-name)
    [ "$i_instance_name" ] && echo "Instance Name: $i_instance_name"
    i_instance_type=$(eval $tencent_req http://169.254.0.23/latest/meta-data/instance/instance-type)
    [ "$i_instance_type" ] && echo "Instance Type: $i_instance_type"
    i_region_id=$(eval $tencent_req http://169.254.0.23/latest/meta-data/placement/region)
    [ "$i_region_id" ] && echo "Region ID: $i_region_id"
    i_zone_id=$(eval $tencent_req http://169.254.0.23/latest/meta-data/placement/zone)
    [ "$i_zone_id" ] && echo "Zone ID: $i_zone_id"

    echo ""
    print_3title "Network Info"
    i_pri_ipv4=$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/primary-local-ipv4)
    [ "$i_pri_ipv4" ] && echo "Primary IPv4: $i_pri_ipv4"

    
    echo "========"
    for mac in $(eval $tencent_req  http://169.254.0.23/latest/meta-data/network/interfaces/macs/); do
      echo "  Mac: $mac"
      echo "  Mac public ips: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/public-ipv4s)
      echo "  Mac vpc id: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/vpc-id)
      echo "  Mac subnet id: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/subnet-id)
      
      for lipv4 in $(eval $tencent_req  http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s); do
        echo "  Mac local ips: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s/$lipv4/local-ipv4)
        echo "  Mac gateways: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s/$lipv4/gateway)
        echo "  Mac public ips: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s/$lipv4/public-ipv4)
        echo "  Mac public ips mode: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s/$lipv4/public-ipv4-mode)
        echo "  Mac subnet mask: "$(eval $tencent_req http://169.254.0.23/latest/meta-data/network/interfaces/macs/$mac/local-ipv4s/$lipv4/subnet-mask)
      done
    echo "======="
    done

    echo ""
    print_3title "Service account "
    for sa in $(eval $tencent_req "http://169.254.0.23/latest/meta-data/cam/security-credentials/"); do 
      echo "  Name: $sa"
      echo "  STS Token: "$(eval $tencent_req "http://169.254.0.23/latest/meta-data/cam/security-credentials/$sa")
      echo "  =============="
    done

    echo ""
    print_3title "Possbile admin ssh Public keys"
    for key in $(eval $tencent_req "http://169.254.0.23/latest/meta-data/public-keys/"); do
      echo "  Name: $key"
      echo "  Key: "$(eval $tencent_req "http://169.254.0.23/latest/meta-data/public-keys/${key}openssh-key")
      echo "  =============="
    done

    echo ""
    print_3title "User Data"
    eval $tencent_req http://169.254.0.23/latest/user-data; echo ""
fi

if [ "$is_aliyun_ecs" = "Yes" ]; then
  aliyun_req=""
  aliyun_token=""
  if [ "$(command -v curl)" ]; then 
    aliyun_token=$(curl -X PUT "http://100.100.100.200/latest/api/token" -H "X-aliyun-ecs-metadata-token-ttl-seconds:1000")
    aliyun_req='curl -s -f -H "X-aliyun-ecs-metadata-token: $aliyun_token"'
  elif [ "$(command -v wget)" ]; then
    aliyun_token=$(wget -q -O - --method PUT "http://100.100.100.200/latest/api/token" --header "X-aliyun-ecs-metadata-token-ttl-seconds:1000")
    aliyun_req='wget -q -O --header "X-aliyun-ecs-metadata-token: $aliyun_token"'
  else 
    echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
  fi

  if [ "$aliyun_token" ]; then
    print_2title "Aliyun ECS Enumeration"
    print_info "https://help.aliyun.com/zh/ecs/user-guide/view-instance-metadata"
    # Todo: print_info "Hacktricks Documents needs to be updated"

    echo ""
    print_3title "Instance Info"
    i_hostname=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/hostname)
    [ "$i_hostname" ] && echo "Hostname: $i_hostname"
    i_instance_id=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/instance-id)
    [ "$i_instance_id" ] && echo "Instance ID: $i_instance_id"
    # no dup of hostname if in ACK it possibly leaks aliyun cluster service ClusterId
    i_instance_name=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/instance/instance-name)
    [ "$i_instance_name" ] && echo "Instance Name: $i_instance_name"
    i_instance_type=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/instance/instance-type)
    [ "$i_instance_type" ] && echo "Instance Type: $i_instance_type"
    i_aliyun_owner_account=$(eval $aliyun_req http://i00.100.100.200/latest/meta-data/owner-account-id)
    [ "$i_aliyun_owner_account" ] && echo "Aliyun Owner Account: $i_aliyun_owner_account"
    i_region_id=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/region-id)
    [ "$i_region_id" ] && echo "Region ID: $i_region_id"
    i_zone_id=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/zone-id)
    [ "$i_zone_id" ] && echo "Zone ID: $i_zone_id"

    echo ""
    print_3title "Network Info"
    i_pub_ipv4=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/public-ipv4)
    [ "$i_pub_ipv4" ] && echo "Public IPv4: $i_pub_ipv4"
    i_priv_ipv4=$(eval $aliyun_req http://100.100.100.200/latest/meta-data/private-ipv4)
    [ "$i_priv_ipv4" ] && echo "Private IPv4: $i_priv_ipv4"
    net_dns=$(eval $aliyun_req  http://100.100.100.200/latest/meta-data/dns-conf/nameservers)
    [ "$net_dns" ] && echo "DNS: $net_dns"
    
    echo "========"
    for mac in $(eval $aliyun_req  http://100.100.100.200/latest/meta-data/network/interfaces/macs/); do
      echo "  Mac: $mac"
      echo "  Mac interface id: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/network-interface-id)
      echo "  Mac netmask: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/netmask)
      echo "  Mac vpc id: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/vpc-id)
      echo "  Mac vpc cidr: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/vpc-cidr-block)
      echo "  Mac vpc cidr (v6): "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/vpc-ipv6-cidr-blocks)
      echo "  Mac vswitch id: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/vswitch-id)
      echo "  Mac vswitch cidr: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/vswitch-cidr-block)
      echo "  Mac vswitch cidr (v6): "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/vswitch-ipv6-cidr-block)
      echo "  Mac private ips: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/private-ipv4s)
      echo "  Mac private ips (v6): "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/ipv6s)
      echo "  Mac gateway: "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/gateway)
      echo "  Mac gateway (v6): "$(eval $aliyun_req http://100.100.100.200/latest/meta-data/network/interfaces/macs/$mac/ipv6-gateway)
      echo "======="
    done

    echo ""
    print_3title "Service account "
    for sa in $(eval $aliyun_req "http://100.100.100.200/latest/meta-data/ram/security-credentials/"); do 
      echo "  Name: $sa"
      echo "  STS Token: "$(eval $aliyun_req "http://100.100.100.200/latest/meta-data/ram/security-credentials/$sa")
      echo "  =============="
    done

    echo ""
    print_3title "Possbile admin ssh Public keys"
    for key in $(eval $aliyun_req "http://100.100.100.200/latest/meta-data/public-keys/"); do
      echo "  Name: $key"
      echo "  Key: "$(eval $aliyun_req "http://100.100.100.200/latest/meta-data/public-keys/${key}openssh-key")
      echo "  =============="
    done


  fi
fi

if [ "$is_gcp_vm" = "Yes" ]; then
    gcp_req=""
    if [ "$(command -v curl)" ]; then
        gcp_req='curl -s -f  -H "Metadata-Flavor: Google"'
    elif [ "$(command -v wget)" ]; then
        gcp_req='wget -q -O - --header "Metadata-Flavor: Google"'
    else 
        echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
    fi

    # GCP Enumeration
    if [ "$gcp_req" ]; then
        print_2title "Google Cloud Platform Enumeration"
        print_info "https://cloud.hacktricks.xyz/pentesting-cloud/gcp-security"

        ## GC Project Info
        p_id=$(eval $gcp_req 'http://metadata.google.internal/computeMetadata/v1/project/project-id')
        [ "$p_id" ] && echo "Project-ID: $p_id"
        p_num=$(eval $gcp_req 'http://metadata.google.internal/computeMetadata/v1/project/numeric-project-id')
        [ "$p_num" ] && echo "Project Number: $p_num"
        pssh_k=$(eval $gcp_req 'http://metadata.google.internal/computeMetadata/v1/project/attributes/ssh-keys')
        [ "$pssh_k" ] && echo "Project SSH-Keys: $pssh_k"
        p_attrs=$(eval $gcp_req 'http://metadata.google.internal/computeMetadata/v1/project/attributes/?recursive=true')
        [ "$p_attrs" ] && echo "All Project Attributes: $p_attrs"

        # OSLogin Info
        osl_u=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/oslogin/users)
        [ "$osl_u" ] && echo "OSLogin users: $osl_u"
        osl_g=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/oslogin/groups)
        [ "$osl_g" ] && echo "OSLogin Groups: $osl_g"
        osl_sk=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/oslogin/security-keys)
        [ "$osl_sk" ] && echo "OSLogin Security Keys: $osl_sk"
        osl_au=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/oslogin/authorize)
        [ "$osl_au" ] && echo "OSLogin Authorize: $osl_au"

        # Instance Info
        inst_d=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/description)
        [ "$inst_d" ] && echo "Instance Description: "
        inst_hostn=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/hostname)
        [ "$inst_hostn" ] && echo "Hostname: $inst_hostn"
        inst_id=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/id)
        [ "$inst_id" ] && echo "Instance ID: $inst_id"
        inst_img=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/image)
        [ "$inst_img" ] && echo "Instance Image: $inst_img"
        inst_mt=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/machine-type)
        [ "$inst_mt" ] && echo "Machine Type: $inst_mt"
        inst_n=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/name)
        [ "$inst_n" ] && echo "Instance Name: $inst_n"
        inst_tag=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/scheduling/tags)
        [ "$inst_tag" ] && echo "Instance tags: $inst_tag"
        inst_zone=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/zone)
        [ "$inst_zone" ] && echo "Zone: $inst_zone"

        inst_k8s_loc=$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster-location")
        [ "$inst_k8s_loc" ] && echo "K8s Cluster Location: $inst_k8s_loc"
        inst_k8s_name=$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster-name")
        [ "$inst_k8s_name" ] && echo "K8s Cluster name: $inst_k8s_name"
        inst_k8s_osl_e=$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/enable-oslogin")
        [ "$inst_k8s_osl_e" ] && echo "K8s OSLoging enabled: $inst_k8s_osl_e"
        inst_k8s_klab=$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/kube-labels")
        [ "$inst_k8s_klab" ] && echo "K8s Kube-labels: $inst_k8s_klab"
        inst_k8s_kubec=$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/kubeconfig")
        [ "$inst_k8s_kubec" ] && echo "K8s Kubeconfig: $inst_k8s_kubec"
        inst_k8s_kubenv=$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/kube-env")
        [ "$inst_k8s_kubenv" ] && echo "K8s Kube-env: $inst_k8s_kubenv"

        echo ""
        print_3title "Interfaces"
        for iface in $(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/"); do 
            echo "  IP: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$iface/ip")
            echo "  Subnetmask: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$iface/subnetmask")
            echo "  Gateway: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$iface/gateway")
            echo "  DNS: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$iface/dns-servers")
            echo "  Network: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/$iface/network")
            echo "  ==============  "
        done
        
        echo ""
        print_3title "User Data"
        echo $(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script")
        echo ""

        echo ""
        print_3title "Service Accounts"
        for sa in $(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/"); do 
            echo "  Name: $sa"
            echo "  Email: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/$sa/email")
            echo "  Aliases: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/$sa/aliases")
            echo "  Identity: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/$sa/identity")
            echo "  Scopes: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/$sa/scopes") | sed -${E} "s,${GCP_GOOD_SCOPES},${SED_GREEN},g" | sed -${E} "s,${GCP_BAD_SCOPES},${SED_RED},g"
            echo "  Token: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/$sa/token")
            echo "  ==============  "
        done
    fi
fi

# Check if the script is running in a GCP Cloud Function
if [ "$is_gcp_function" = "Yes" ]; then
    gcp_req=""
    if [ "$(command -v curl)" ]; then
        gcp_req='curl -s -f  -H "Metadata-Flavor: Google"'
    elif [ "$(command -v wget)" ]; then
        gcp_req='wget -q -O - --header "Metadata-Flavor: Google"'
    else 
        echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
    fi

    # GCP Enumeration
    if [ "$gcp_req" ]; then
        print_2title "Google Cloud Platform Enumeration"
        print_info "https://cloud.hacktricks.xyz/pentesting-cloud/gcp-security"

        ## GC Project Info
        p_id=$(eval $gcp_req 'http://metadata.google.internal/computeMetadata/v1/project/project-id')
        [ "$p_id" ] && echo "Project-ID: $p_id"
        p_num=$(eval $gcp_req 'http://metadata.google.internal/computeMetadata/v1/project/numeric-project-id')
        [ "$p_num" ] && echo "Project Number: $p_num"

        # Instance Info
        inst_id=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/id)
        [ "$inst_id" ] && echo "Instance ID: $inst_id"
        mtls_info=$(eval $gcp_req http://metadata/computeMetadata/v1/instance/platform-security/auto-mtls-configuration)
        [ "$mtls_info" ] && echo "MTLS info: $mtls_info"
        inst_zone=$(eval $gcp_req http://metadata.google.internal/computeMetadata/v1/instance/zone)
        [ "$inst_zone" ] && echo "Zone: $inst_zone"

        echo ""
        print_3title "Service Accounts"
        for sa in $(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/"); do 
            echo "  Name: $sa"
            echo "  Email: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/${sa}email")
            echo "  Aliases: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/${sa}aliases")
            echo "  Identity: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/${sa}identity")
            echo "  Scopes: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/${sa}scopes") | sed -${E} "s,${GCP_GOOD_SCOPES},${SED_GREEN},g" | sed -${E} "s,${GCP_BAD_SCOPES},${SED_RED},g"
            echo "  Token: "$(eval $gcp_req "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/${sa}token")
            echo "  ==============  "
        done
    fi
fi


curl "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/405423052163-compute@developer.gserviceaccount.com/email"

# AWS ECS Enumeration
if [ "$is_aws_ecs" = "Yes" ]; then
    print_2title "AWS ECS Enumeration"
    
    aws_ecs_req=""
    if [ "$(command -v curl)" ]; then
        aws_ecs_req='curl -s -f'
    elif [ "$(command -v wget)" ]; then
        aws_ecs_req='wget -q -O -'
    else 
        echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
    fi

    if [ "$aws_ecs_metadata_uri" ]; then
        print_3title "Container Info"
        exec_with_jq eval $aws_ecs_req "$aws_ecs_metadata_uri"
        echo ""
        
        print_3title "Task Info"
        exec_with_jq eval $aws_ecs_req "$aws_ecs_metadata_uri/task"
        echo ""
    else
        echo "I couldn't find ECS_CONTAINER_METADATA_URI env var to get container info"
    fi

    if [ "$aws_ecs_service_account_uri" ]; then
        print_3title "IAM Role"
        exec_with_jq eval $aws_ecs_req "$aws_ecs_service_account_uri"
        echo ""
    else
        echo "I couldn't find AWS_CONTAINER_CREDENTIALS_RELATIVE_URI env var to get IAM role info (the task is running without a task role probably)"
    fi
fi

# AWS EC2 Enumeration
if [ "$is_aws_ec2" = "Yes" ]; then
    print_2title "AWS EC2 Enumeration"
    
    HEADER="X-aws-ec2-metadata-token: $EC2_TOKEN"
    URL="http://169.254.169.254/latest/meta-data"
    
    aws_req=""
    if [ "$(command -v curl)" ]; then
        aws_req="curl -s -f -H '$HEADER'"
    elif [ "$(command -v wget)" ]; then
        aws_req="wget -q -O - -H '$HEADER'"
    else 
        echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
    fi
  
    if [ "$aws_req" ]; then
        printf "ami-id: "; eval $aws_req "$URL/ami-id"; echo ""
        printf "instance-action: "; eval $aws_req "$URL/instance-action"; echo ""
        printf "instance-id: "; eval $aws_req "$URL/instance-id"; echo ""
        printf "instance-life-cycle: "; eval $aws_req "$URL/instance-life-cycle"; echo ""
        printf "instance-type: "; eval $aws_req "$URL/instance-type"; echo ""
        printf "region: "; eval $aws_req "$URL/placement/region"; echo ""

        echo ""
        print_3title "Account Info"
        exec_with_jq eval $aws_req "$URL/identity-credentials/ec2/info"; echo ""

        echo ""
        print_3title "Network Info"
        for mac in $(eval $aws_req "$URL/network/interfaces/macs/" 2>/dev/null); do 
          echo "Mac: $mac"
          printf "Owner ID: "; eval $aws_req "$URL/network/interfaces/macs/$mac/owner-id"; echo ""
          printf "Public Hostname: "; eval $aws_req "$URL/network/interfaces/macs/$mac/public-hostname"; echo ""
          printf "Security Groups: "; eval $aws_req "$URL/network/interfaces/macs/$mac/security-groups"; echo ""
          echo "Private IPv4s:"; eval $aws_req "$URL/network/interfaces/macs/$mac/ipv4-associations/"; echo ""
          printf "Subnet IPv4: "; eval $aws_req "$URL/network/interfaces/macs/$mac/subnet-ipv4-cidr-block"; echo ""
          echo "PrivateIPv6s:"; eval $aws_req "$URL/network/interfaces/macs/$mac/ipv6s"; echo ""
          printf "Subnet IPv6: "; eval $aws_req "$URL/network/interfaces/macs/$mac/subnet-ipv6-cidr-blocks"; echo ""
          echo "Public IPv4s:"; eval $aws_req "$URL/network/interfaces/macs/$mac/public-ipv4s"; echo ""
          echo ""
        done

        echo ""
        print_3title "IAM Role"
        exec_with_jq eval $aws_req "$URL/iam/info"; echo ""
        for role in $(eval $aws_req "$URL/iam/security-credentials/" 2>/dev/null); do 
          echo "Role: $role"
          exec_with_jq eval $aws_req "$URL/iam/security-credentials/$role"; echo ""
          echo ""
        done
        
        echo ""
        print_3title "User Data"
        eval $aws_req "http://169.254.169.254/latest/user-data"; echo ""
        
        echo ""
        echo "EC2 Security Credentials"
        exec_with_jq eval $aws_req "$URL/identity-credentials/ec2/security-credentials/ec2-instance"; echo ""
        
        print_3title "SSM Runnig"
        ps aux 2>/dev/null | grep "ssm-agent" | grep -v "grep" | sed "s,ssm-agent,${SED_RED},"
    fi
fi

# AWS Lambda Enumeration
if [ "$is_aws_lambda" = "Yes" ]; then
  print_2title "AWS Lambda Enumeration"
  printf "Function name: "; env | grep AWS_LAMBDA_FUNCTION_NAME
  printf "Region: "; env | grep AWS_REGION
  printf "Secret Access Key: "; env | grep AWS_SECRET_ACCESS_KEY
  printf "Access Key ID: "; env | grep AWS_ACCESS_KEY_ID
  printf "Session token: "; env | grep AWS_SESSION_TOKEN
  printf "Security token: "; env | grep AWS_SECURITY_TOKEN
  printf "Runtime API: "; env | grep AWS_LAMBDA_RUNTIME_API
  printf "Event data: "; (curl -s "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next" 2>/dev/null || wget -q -O - "http://${AWS_LAMBDA_RUNTIME_API}/2018-06-01/runtime/invocation/next")
fi

# AWS Codebuild Enumeration
if [ "$is_aws_codebuild" = "Yes" ]; then
  print_2title "AWS Codebuild Enumeration"

  aws_req=""
  if [ "$(command -v curl)" ]; then
      aws_req="curl -s -f"
  elif [ "$(command -v wget)" ]; then
      aws_req="wget -q -O -"
  else 
      echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
      echo "The addresses are in /codebuild/output/tmp/env.sh"
  fi

  if [ "$aws_req" ]; then
    print_3title "Credentials"
    CREDS_PATH=$(cat /codebuild/output/tmp/env.sh | grep "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" | cut -d "'" -f 2)
    URL_CREDS="http://169.254.170.2$CREDS_PATH" # Already has a / at the begginig
    exec_with_jq eval $aws_req "$URL_CREDS"; echo ""

    print_3title "Container Info"
    METADATA_URL=$(cat /codebuild/output/tmp/env.sh | grep "ECS_CONTAINER_METADATA_URI" | cut -d "'" -f 2)
    exec_with_jq eval $aws_req "$METADATA_URL"; echo ""
  fi
fi

# DO Droplet Enumeration
if [ "$is_do" = "Yes" ]; then
  print_2title "DO Droplet Enumeration"

  do_req=""
  if [ "$(command -v curl)" ]; then
      do_req='curl -s -f '
  elif [ "$(command -v wget)" ]; then
      do_req='wget -q -O - '
  else 
      echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
  fi

  if [ "$do_req" ]; then
    URL="http://169.254.169.254/metadata"
    printf "Id: "; eval $do_req "$URL/v1/id"; echo ""
    printf "Region: "; eval $do_req "$URL/v1/region"; echo ""
    printf "Public keys: "; eval $do_req "$URL/v1/public-keys"; echo ""
    printf "User data: "; eval $do_req "$URL/v1/user-data"; echo ""
    printf "Dns: "; eval $do_req "$URL/v1/dns/nameservers" | tr '\n' ','; echo ""
    printf "Interfaces: "; eval $do_req "$URL/v1.json" | jq ".interfaces";
    printf "Floating_ip: "; eval $do_req "$URL/v1.json" | jq ".floating_ip";
    printf "Reserved_ip: "; eval $do_req "$URL/v1.json" | jq ".reserved_ip";
    printf "Tags: "; eval $do_req "$URL/v1.json" | jq ".tags";
    printf "Features: "; eval $do_req "$URL/v1.json" | jq ".features";
  fi
fi

# IBM Cloud Enumeration
if [ "$is_ibm_vm" = "Yes" ]; then
  print_2title "IBM Cloud Enumeration"

  if ! [ "$IBM_TOKEN" ]; then
    echo "Couldn't get the metadata token:("

  else
    TOKEN_HEADER="Authorization: Bearer $IBM_TOKEN"
    ACCEPT_HEADER="Accept: application/json"
    URL="http://169.254.169.254/latest/meta-data"
    
    ibm_req=""
    if [ "$(command -v curl)" ]; then
        ibm_req="curl -s -f -H '$TOKEN_HEADER' -H '$ACCEPT_HEADER'"
    elif [ "$(command -v wget)" ]; then
        ibm_req="wget -q -O - -H '$TOKEN_HEADER' -H '$ACCEPT_HEADER'"
    else 
        echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
    fi

    if [ "$ibm_req" ]; then
      print_3title "Instance Details"
      exec_with_jq eval $ibm_req "http://169.254.169.254/metadata/v1/instance?version=2022-03-01"

      print_3title "Keys and User data"
      exec_with_jq eval $ibm_req "http://169.254.169.254/metadata/v1/instance/initialization?version=2022-03-01"
      exec_with_jq eval $ibm_req "http://169.254.169.254/metadata/v1/keys?version=2022-03-01"

      print_3title "Placement Groups"
      exec_with_jq eval $ibm_req "http://169.254.169.254/metadata/v1/placement_groups?version=2022-03-01"

      print_3title "IAM credentials"
      exec_with_jq eval $ibm_req -X POST "http://169.254.169.254/instance_identity/v1/iam_token?version=2022-03-01"
    fi
  fi

fi

# Azure VM Enumeration
if [ "$is_az_vm" = "Yes" ]; then
  print_2title "Azure VM Enumeration"

  HEADER="Metadata:true"
  URL="http://169.254.169.254/metadata"
  API_VERSION="2021-12-13" # https://learn.microsoft.com/en-us/azure/virtual-machines/instance-metadata-service?tabs=linux#supported-api-versions
  
  az_req=""
  if [ "$(command -v curl)" ]; then
      az_req="curl -s -f -H '$HEADER'"
  elif [ "$(command -v wget)" ]; then
      az_req="wget -q -O - -H '$HEADER'"
  else 
      echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
  fi

  if [ "$az_req" ]; then
    print_3title "Instance details"
    exec_with_jq eval $az_req "$URL/instance?api-version=$API_VERSION"

    print_3title "Load Balancer details"
    exec_with_jq eval $az_req "$URL/loadbalancer?api-version=$API_VERSION"

    print_3title "Management token"
    exec_with_jq eval $az_req "$URL/identity/oauth2/token?api-version=$API_VERSION\&resource=https://management.azure.com/"

    print_3title "Graph token"
    exec_with_jq eval $az_req "$URL/identity/oauth2/token?api-version=$API_VERSION\&resource=https://graph.microsoft.com/"
    
    print_3title "Vault token"
    exec_with_jq eval $az_req "$URL/identity/oauth2/token?api-version=$API_VERSION\&resource=https://vault.azure.net/"

    print_3title "Storage token"
    exec_with_jq eval $az_req "$URL/identity/oauth2/token?api-version=$API_VERSION\&resource=https://storage.azure.com/"
  fi
fi

if [ "$check_az_app" = "Yes" ]; then
  print_2title "Azure App Service Enumeration"
  echo "I haven't tested this one, if it doesn't work, please send a PR fixing and adding functionality :)"

  HEADER="secret:$IDENTITY_HEADER"

  az_req=""
  if [ "$(command -v curl)" ]; then
      az_req="curl -s -f -H '$HEADER'"
  elif [ "$(command -v wget)" ]; then
      az_req="wget -q -O - -H '$HEADER'"
  else 
      echo "Neither curl nor wget were found, I can't enumerate the metadata service :("
  fi

  if [ "$az_req" ]; then
    print_3title "Management token"
    exec_with_jq eval $az_req "$IDENTITY_ENDPOINT?api-version=$API_VERSION\&resource=https://management.azure.com/"

    print_3title "Graph token"
    exec_with_jq eval $az_req "$IDENTITY_ENDPOINT?api-version=$API_VERSION\&resource=https://graph.microsoft.com/"
    
    print_3title "Vault token"
    exec_with_jq eval $az_req "$IDENTITY_ENDPOINT?api-version=$API_VERSION\&resource=https://vault.azure.net/"

    print_3title "Storage token"
    exec_with_jq eval $az_req "$IDENTITY_ENDPOINT?api-version=$API_VERSION\&resource=https://storage.azure.com/"
  fi
fi
