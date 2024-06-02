###########################################
#---------) Container functions (---------#
###########################################

containerCheck() {
  inContainer=""
  containerType="$(echo_no)"

  # Are we inside docker?
  if [ -f "/.dockerenv" ] ||
    grep "/docker/" /proc/1/cgroup -qa 2>/dev/null ||
    grep -qai docker /proc/self/cgroup  2>/dev/null ||
    [ "$(find / -maxdepth 3 -name '*dockerenv*' -exec ls -la {} \; 2>/dev/null)" ] ; then

    inContainer="1"
    containerType="docker\n"
  fi

  # Are we inside kubernetes?
  if grep "/kubepod" /proc/1/cgroup -qa 2>/dev/null ||
    grep -qai kubepods /proc/self/cgroup 2>/dev/null; then

    inContainer="1"
    if [ "$containerType" ]; then containerType="$containerType (kubernetes)\n"
    else containerType="kubernetes\n"
    fi
  fi
  
  # Inside concourse?
  if grep "/concourse" /proc/1/mounts -qa 2>/dev/null; then
    inContainer="1"
    if [ "$containerType" ]; then 
      containerType="$containerType (concourse)\n"
    fi
  fi

  # Are we inside LXC?
  if env | grep "container=lxc" -qa 2>/dev/null ||
      grep "/lxc/" /proc/1/cgroup -qa 2>/dev/null; then

    inContainer="1"
    containerType="lxc\n"
  fi

  # Are we inside podman?
  if env | grep -qa "container=podman" 2>/dev/null ||
      grep -qa "container=podman" /proc/1/environ 2>/dev/null; then

    inContainer="1"
    containerType="podman\n"
  fi

  # Check for other container platforms that report themselves in PID 1 env
  if [ -z "$inContainer" ]; then
    if grep -a 'container=' /proc/1/environ 2>/dev/null; then
      inContainer="1"
      containerType="$(grep -a 'container=' /proc/1/environ | cut -d= -f2)\n"
    fi
  fi
}

inDockerGroup() {
  DOCKER_GROUP="No"
  if groups 2>/dev/null | grep -q '\bdocker\b'; then
    DOCKER_GROUP="Yes"
  fi
}

checkDockerRootless() {
  DOCKER_ROOTLESS="No"
  if docker info 2>/dev/null|grep -q rootless; then
    DOCKER_ROOTLESS="Yes ($TIP_DOCKER_ROOTLESS)"
  fi
}

enumerateDockerSockets() {
  dockerVersion="$(echo_not_found)"
  if ! [ "$SEARCHED_DOCKER_SOCKETS" ]; then
    SEARCHED_DOCKER_SOCKETS="1"
    for int_sock in $(find / ! -path "/sys/*" -type s -name "docker.sock" -o -name "docker.socket" -o -name "dockershim.sock" -o -name "containerd.sock" -o -name "crio.sock" -o -name "frakti.sock" -o -name "rktlet.sock" 2>/dev/null); do
      if ! [ "$IAMROOT" ] && [ -w "$int_sock" ]; then
        if echo "$int_sock" | grep -Eq "docker"; then
          dock_sock="$int_sock"
          echo "You have write permissions over Docker socket $dock_sock" | sed -${E} "s,$dock_sock,${SED_RED_YELLOW},g"
          echo "Docker enummeration:"
          docker_enumerated=""

          if [ "$(command -v curl)" ]; then
            sockInfoResponse="$(curl -s --unix-socket $dock_sock http://localhost/info)"
            dockerVersion=$(echo "$sockInfoResponse" | tr ',' '\n' | grep 'ServerVersion' | cut -d'"' -f 4)
            echo $sockInfoResponse | tr ',' '\n' | grep -E "$GREP_DOCKER_SOCK_INFOS" | grep -v "$GREP_DOCKER_SOCK_INFOS_IGNORE" | tr -d '"'
            if [ "$sockInfoResponse" ]; then docker_enumerated="1"; fi
          fi

          if [ "$(command -v docker)" ] && ! [ "$docker_enumerated" ]; then
            sockInfoResponse="$(docker info)"
            dockerVersion=$(echo "$sockInfoResponse" | tr ',' '\n' | grep 'Server Version' | cut -d' ' -f 4)
            printf "$sockInfoResponse" | tr ',' '\n' | grep -E "$GREP_DOCKER_SOCK_INFOS" | grep -v "$GREP_DOCKER_SOCK_INFOS_IGNORE" | tr -d '"'
          fi
        
        else
          echo "You have write permissions over interesting socket $int_sock" | sed -${E} "s,$int_sock,${SED_RED},g"
        fi

      else
        echo "You don't have write permissions over interesting socket $int_sock" | sed -${E} "s,$int_sock,${SED_GREEN},g"
      fi
    done
  fi
}

checkDockerVersionExploits() {
  if echo "$dockerVersion" | grep -iq "not found"; then
    VULN_CVE_2019_13139="$(echo_not_found)"
    VULN_CVE_2019_5736="$(echo_not_found)"
    VULN_CVE_2021_41091="$(echo_not_found)"
    return
  fi

  VULN_CVE_2019_13139="$(echo_no)"
  if [ "$(echo $dockerVersion | sed 's,\.,,g')" -lt "1895" ]; then
    VULN_CVE_2019_13139="Yes"
  fi

  VULN_CVE_2019_5736="$(echo_no)"
  if [ "$(echo $dockerVersion | sed 's,\.,,g')" -lt "1893" ]; then
    VULN_CVE_2019_5736="Yes"
  fi

  VULN_CVE_2021_41091="$(echo_no)"
  if [ "$(echo $dockerVersion | sed 's,\.,,g')" -lt "20109" ]; then
    VULN_CVE_2021_41091="Yes"
  fi
}

checkContainerExploits() {
  VULN_CVE_2019_5021="$(echo_no)"
  if [ -f "/etc/alpine-release" ]; then
    alpineVersion=$(cat /etc/alpine-release)
    if [ "$(echo $alpineVersion | sed 's,\.,,g')" -ge "330" ] && [ "$(echo $alpineVersion | sed 's,\.,,g')" -le "360" ]; then
      VULN_CVE_2019_5021="Yes"
    fi
  fi
}

checkCreateReleaseAgent(){
  cat /proc/$$/cgroup 2>/dev/null | grep -Eo '[0-9]+:[^:]+' | grep -Eo '[^:]+$' | while read -r subsys
  do
      if unshare -UrmC --propagation=unchanged bash -c "mount -t cgroup -o $subsys cgroup /tmp/cgroup_3628d4 2>&1 >/dev/null && test -w /tmp/cgroup_3628d4/release_agent" >/dev/null 2>&1 ; then
          release_agent_breakout2="Yes (unshare with $subsys)";
          rm -rf /tmp/cgroup_3628d4
          break
      fi
  done
}

checkProcSysBreakouts(){
  dev_mounted="No"
  if [ $(ls -l /dev | grep -E "^c" | wc -l) -gt 50 ]; then
    dev_mounted="Yes";
  fi

  proc_mounted="No"
  if [ $(ls /proc | grep -E "^[0-9]" | wc -l) -gt 50 ]; then
    proc_mounted="Yes";
  fi

  run_unshare=$(unshare -UrmC bash -c 'echo -n Yes' 2>/dev/null)
  if ! [ "$run_unshare" = "Yes" ]; then
    run_unshare="No"
  fi

  if [ "$(ls -l /sys/fs/cgroup/*/release_agent 2>/dev/null)" ]; then 
    release_agent_breakout1="Yes"
  else 
    release_agent_breakout1="No"
  fi
  
  release_agent_breakout2="No"
  mkdir /tmp/cgroup_3628d4
  mount -t cgroup -o memory cgroup /tmp/cgroup_3628d4 2>/dev/null
  if [ $? -eq 0 ]; then 
    release_agent_breakout2="Yes"; 
    rm -rf /tmp/cgroup_3628d4
  else 
    mount -t cgroup -o rdma cgroup /tmp/cgroup_3628d4 2>/dev/null
    if [ $? -eq 0 ]; then 
      release_agent_breakout2="Yes"; 
      rm -rf /tmp/cgroup_3628d4
    else 
      checkCreateReleaseAgent
    fi
  fi
  rm -rf /tmp/cgroup_3628d4 2>/dev/null
  
  core_pattern_breakout="$( (echo -n '' > /proc/sys/kernel/core_pattern && echo Yes) 2>/dev/null || echo No)"
  modprobe_present="$(ls -l `cat /proc/sys/kernel/modprobe` 2>/dev/null || echo No)"
  panic_on_oom_dos="$( (echo -n '' > /proc/sys/vm/panic_on_oom && echo Yes) 2>/dev/null || echo No)"
  panic_sys_fs_dos="$( (echo -n '' > /proc/sys/fs/suid_dumpable && echo Yes) 2>/dev/null || echo No)"
  binfmt_misc_breakout="$( (echo -n '' > /proc/sys/fs/binfmt_misc/register && echo Yes) 2>/dev/null || echo No)"
  proc_configgz_readable="$([ -r '/proc/config.gz' ] 2>/dev/null && echo Yes || echo No)"
  sysreq_trigger_dos="$( (echo -n '' > /proc/sysrq-trigger && echo Yes) 2>/dev/null || echo No)"
  kmsg_readable="$( (dmesg > /dev/null 2>&1 && echo Yes) 2>/dev/null || echo No)"  # Kernel Exploit Dev
  kallsyms_readable="$( (head -n 1 /proc/kallsyms > /dev/null && echo Yes )2>/dev/null || echo No)" # Kernel Exploit Dev
  mem_readable="$( (head -n 1 /proc/self/mem > /dev/null && echo Yes) 2>/dev/null || echo No)"
  if [ "$(head -n 1 /tmp/kcore 2>/dev/null)" ]; then kcore_readable="Yes"; else kcore_readable="No"; fi
  kmem_readable="$( (head -n 1 /proc/kmem > /dev/null && echo Yes) 2>/dev/null || echo No)"
  kmem_writable="$( (echo -n '' > /proc/kmem > /dev/null && echo Yes) 2>/dev/null || echo No)"
  mem_readable="$( (head -n 1 /proc/mem > /dev/null && echo Yes) 2>/dev/null || echo No)"
  mem_writable="$( (echo -n '' > /proc/mem > /dev/null && echo Yes) 2>/dev/null || echo No)"
  sched_debug_readable="$( (head -n 1 /proc/sched_debug > /dev/null && echo Yes) 2>/dev/null || echo No)"
  mountinfo_readable="$( (head -n 1 /proc/*/mountinfo > /dev/null && echo Yes) 2>/dev/null || echo No)"
  uevent_helper_breakout="$( (echo -n '' > /sys/kernel/uevent_helper && echo Yes) 2>/dev/null || echo No)"
  vmcoreinfo_readable="$( (head -n 1 /sys/kernel/vmcoreinfo > /dev/null && echo Yes) 2>/dev/null || echo No)"
  security_present="$( (ls -l /sys/kernel/security > /dev/null && echo Yes) 2>/dev/null || echo No)"
  security_writable="$( (echo -n '' > /sys/kernel/security/a && echo Yes) 2>/dev/null || echo No)"
  efi_vars_writable="$( (echo -n '' > /sys/firmware/efi/vars && echo Yes) 2>/dev/null || echo No)"
  efi_efivars_writable="$( (echo -n '' > /sys/firmware/efi/efivars && echo Yes) 2>/dev/null || echo No)"
}


##############################################
#---------------) Containers (---------------#
##############################################
containerCheck

print_2title "Container related tools present (if any):"
command -v docker 
command -v lxc 
command -v rkt 
command -v kubectl
command -v podman
command -v runc

if [ "$$FAT_LINPEAS_AMICONTAINED" ]; then
  print_2title "Am I Containered?"
  execBin "AmIContainered" "https://github.com/genuinetools/amicontained" "$FAT_LINPEAS_AMICONTAINED"
fi

print_2title "Container details"
print_list "Is this a container? ...........$NC $containerType"

print_list "Any running containers? ........ "$NC
# Get counts of running containers for each platform
dockercontainers=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l)
podmancontainers=$(podman ps --format "{{.Names}}" 2>/dev/null | wc -l)
lxccontainers=$(lxc list -c n --format csv 2>/dev/null | wc -l)
rktcontainers=$(rkt list 2>/dev/null | tail -n +2  | wc -l)
if [ "$dockercontainers" -eq "0" ] && [ "$lxccontainers" -eq "0" ] && [ "$rktcontainers" -eq "0" ] && [ "$podmancontainers" -eq "0" ]; then
    echo_no
else
    containerCounts=""
    if [ "$dockercontainers" -ne "0" ]; then containerCounts="${containerCounts}docker($dockercontainers) "; fi
    if [ "$podmancontainers" -ne "0" ]; then containerCounts="${containerCounts}podman($podmancontainers) "; fi
    if [ "$lxccontainers" -ne "0" ]; then containerCounts="${containerCounts}lxc($lxccontainers) "; fi
    if [ "$rktcontainers" -ne "0" ]; then containerCounts="${containerCounts}rkt($rktcontainers) "; fi
    echo "Yes $containerCounts" | sed -${E} "s,.*,${SED_RED},"
    
    # List any running containers
    if [ "$dockercontainers" -ne "0" ]; then echo "Running Docker Containers" | sed -${E} "s,.*,${SED_RED},"; docker ps | tail -n +2 2>/dev/null; echo ""; fi
    if [ "$podmancontainers" -ne "0" ]; then echo "Running Podman Containers" | sed -${E} "s,.*,${SED_RED},"; podman ps | tail -n +2 2>/dev/null; echo ""; fi
    if [ "$lxccontainers" -ne "0" ]; then echo "Running LXC Containers" | sed -${E} "s,.*,${SED_RED},"; lxc list 2>/dev/null; echo ""; fi
    if [ "$rktcontainers" -ne "0" ]; then echo "Running RKT Containers" | sed -${E} "s,.*,${SED_RED},"; rkt list 2>/dev/null; echo ""; fi
fi

# If docker
if echo "$containerType" | grep -qi "docker"; then
    print_2title "Docker Container details"
    inDockerGroup
    print_list "Am I inside Docker group .......$NC $DOCKER_GROUP\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "Looking and enumerating Docker Sockets (if any):\n"$NC
    enumerateDockerSockets
    print_list "Docker version .................$NC$dockerVersion"
    checkDockerVersionExploits
    print_list "Vulnerable to CVE-2019-5736 ....$NC$VULN_CVE_2019_5736"$NC | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "Vulnerable to CVE-2019-13139 ...$NC$VULN_CVE_2019_13139"$NC | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "Vulnerable to CVE-2021-41091 ...$NC$VULN_CVE_2021_41091"$NC | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    if [ "$inContainer" ]; then
        checkDockerRootless
        print_list "Rootless Docker? ............... $DOCKER_ROOTLESS\n"$NC | sed -${E} "s,No,${SED_RED}," | sed -${E} "s,Yes,${SED_GREEN},"
        echo ""
    fi
    if df -h | grep docker; then
        print_2title "Docker Overlays"
        df -h | grep docker
    fi
fi

# If token secrets mounted
if [ "$(mount | sed -n '/secret/ s/^tmpfs on \(.*default.*\) type tmpfs.*$/\1\/namespace/p')" ]; then
  print_2title "Listing mounted tokens"
  print_info "https://cloud.hacktricks.xyz/pentesting-cloud/kubernetes-security/attacking-kubernetes-from-inside-a-pod"
  ALREADY="IinItialVaaluE"
  for i in $(mount | sed -n '/secret/ s/^tmpfs on \(.*default.*\) type tmpfs.*$/\1\/namespace/p'); do
      TOKEN=$(cat $(echo $i | sed 's/.namespace$/\/token/'))
      if ! [ $(echo $TOKEN | grep -E $ALREADY) ]; then
          ALREADY="$ALREADY|$TOKEN"
          echo "Directory: $i"
          echo "Namespace: $(cat $i)"
          echo ""
          echo $TOKEN
          echo "================================================================================"
          echo ""
      fi
  done
fi

if [ "$inContainer" ]; then
    echo ""
    print_2title "Container & breakout enumeration"
    print_info "https://book.hacktricks.xyz/linux-hardening/privilege-escalation/docker-breakout"
    print_list "Container ID ...................$NC $(cat /etc/hostname && echo -n '\n')"
    if [ -f "/proc/1/cpuset" ] && echo "$containerType" | grep -qi "docker"; then
        print_list "Container Full ID ..............$NC $(basename $(cat /proc/1/cpuset))\n"
    fi
    print_list "Seccomp enabled? ............... "$NC
    ([ "$(grep Seccomp /proc/self/status | grep -v 0)" ] && echo "enabled" || echo "disabled") | sed "s,disabled,${SED_RED}," | sed "s,enabled,${SED_GREEN},"

    print_list "AppArmor profile? .............. "$NC
    (cat /proc/self/attr/current 2>/dev/null || echo "disabled") | sed "s,disabled,${SED_RED}," | sed "s,kernel,${SED_GREEN},"

    print_list "User proc namespace? ........... "$NC
    if [ "$(cat /proc/self/uid_map 2>/dev/null)" ]; then (printf "enabled"; cat /proc/self/uid_map) | sed "s,enabled,${SED_GREEN},"; else echo "disabled" | sed "s,disabled,${SED_RED},"; fi

    checkContainerExploits
    print_list "Vulnerable to CVE-2019-5021 .... $VULN_CVE_2019_5021\n"$NC | sed -${E} "s,Yes,${SED_RED_YELLOW},"

    print_3title "Breakout via mounts"
    print_info "https://book.hacktricks.xyz/linux-hardening/privilege-escalation/docker-breakout/docker-breakout-privilege-escalation/sensitive-mounts"
    
    checkProcSysBreakouts
    print_list "/proc mounted? ................. $proc_mounted\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "/dev mounted? .................. $dev_mounted\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "Run unshare .................... $run_unshare\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "release_agent breakout 1........ $release_agent_breakout1\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "release_agent breakout 2........ $release_agent_breakout2\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "core_pattern breakout .......... $core_pattern_breakout\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "binfmt_misc breakout ........... $binfmt_misc_breakout\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "uevent_helper breakout ......... $uevent_helper_breakout\n" | sed -${E} "s,Yes,${SED_RED_YELLOW},"
    print_list "is modprobe present ............ $modprobe_present\n" | sed -${E} "s,/.*,${SED_RED},"
    print_list "DoS via panic_on_oom ........... $panic_on_oom_dos\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "DoS via panic_sys_fs ........... $panic_sys_fs_dos\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "DoS via sysreq_trigger_dos ..... $sysreq_trigger_dos\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "/proc/config.gz readable ....... $proc_configgz_readable\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "/proc/sched_debug readable ..... $sched_debug_readable\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "/proc/*/mountinfo readable ..... $mountinfo_readable\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "/sys/kernel/security present ... $security_present\n" | sed -${E} "s,Yes,${SED_RED},"
    print_list "/sys/kernel/security writable .. $security_writable\n" | sed -${E} "s,Yes,${SED_RED},"
    if [ "$EXTRA_CHECKS" ]; then
      print_list "/proc/kmsg readable ............ $kmsg_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/kallsyms readable ........ $kallsyms_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/self/mem readable ........ $sched_debug_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/kcore readable ........... $kcore_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/kmem readable ............ $kmem_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/kmem writable ............ $kmem_writable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/mem readable ............. $mem_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/proc/mem writable ............. $mem_writable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/sys/kernel/vmcoreinfo readable  $vmcoreinfo_readable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/sys/firmware/efi/vars writable  $efi_vars_writable\n" | sed -${E} "s,Yes,${SED_RED},"
      print_list "/sys/firmware/efi/efivars writable $efi_efivars_writable\n" | sed -${E} "s,Yes,${SED_RED},"
    fi
    
    echo ""
    print_3title "Namespaces"
    print_info "https://book.hacktricks.xyz/linux-hardening/privilege-escalation/docker-breakout/namespaces"
    ls -l /proc/self/ns/

    if echo "$containerType" | grep -qi "kubernetes"; then
        print_list "Kubernetes namespace ...........$NC $(cat /run/secrets/kubernetes.io/serviceaccount/namespace /var/run/secrets/kubernetes.io/serviceaccount/namespace /secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null)\n"
        print_list "Kubernetes token ...............$NC $(cat /run/secrets/kubernetes.io/serviceaccount/token /var/run/secrets/kubernetes.io/serviceaccount/token /secrets/kubernetes.io/serviceaccount/token 2>/dev/null)\n"
        echo ""
        
        print_2title "Kubernetes Information"
        print_info "https://cloud.hacktricks.xyz/pentesting-cloud/kubernetes-security/attacking-kubernetes-from-inside-a-pod"
        
        
        print_3title "Kubernetes service account folder"
        ls -lR /run/secrets/kubernetes.io/ /var/run/secrets/kubernetes.io/ /secrets/kubernetes.io/ 2>/dev/null
        echo ""
        
        print_3title "Kubernetes env vars"
        (env | set) | grep -Ei "kubernetes|kube" | grep -Ev "^WF=|^Wfolders=|^mounted=|^USEFUL_SOFTWARE='|^INT_HIDDEN_FILES=|^containerType="
        echo ""

        print_3title "Current sa user k8s permissions"
        print_info "https://cloud.hacktricks.xyz/pentesting-cloud/kubernetes-security/abusing-roles-clusterroles-in-kubernetes"
        kubectl auth can-i --list 2>/dev/null || curl -s -k -d "$(echo \"eyJraW5kIjoiU2VsZlN1YmplY3RSdWxlc1JldmlldyIsImFwaVZlcnNpb24iOiJhdXRob3JpemF0aW9uLms4cy5pby92MSIsIm1ldGFkYXRhIjp7ImNyZWF0aW9uVGltZXN0YW1wIjpudWxsfSwic3BlYyI6eyJuYW1lc3BhY2UiOiJlZXZlZSJ9LCJzdGF0dXMiOnsicmVzb3VyY2VSdWxlcyI6bnVsbCwibm9uUmVzb3VyY2VSdWxlcyI6bnVsbCwiaW5jb21wbGV0ZSI6ZmFsc2V9fQo=\"|base64 -d)" \
          "https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}/apis/authorization.k8s.io/v1/selfsubjectrulesreviews" \
            -X 'POST' -H 'Content-Type: application/json' \
            --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" | sed "s,secrets|exec|create|patch|impersonate|\"*\",${SED_RED},"

    fi
    echo ""

    print_2title "Container Capabilities"
    print_info "https://book.hacktricks.xyz/linux-hardening/privilege-escalation/docker-breakout/docker-breakout-privilege-escalation#capabilities-abuse-escape"
    if [ "$(command -v capsh)" ]; then 
      capsh --print 2>/dev/null | sed -${E} "s,$containercapsB,${SED_RED},g"
    else
      defautl_docker_caps="00000000a80425fb=cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap"
      cat /proc/self/status | tr '\t' ' ' | grep Cap | sed -${E} "s, .*,${SED_RED},g" | sed -${E} "s/00000000a80425fb/$defautl_docker_caps/g" | sed -${E} "s,0000000000000000|00000000a80425fb,${SED_GREEN},g"
      echo $ITALIC"Run capsh --decode=<hex> to decode the capabilities"$NC
    fi
    echo ""

    print_2title "Privilege Mode"
    if [ -x "$(command -v fdisk)" ]; then
        if [ "$(fdisk -l 2>/dev/null | wc -l)" -gt 0 ]; then
            echo "Privilege Mode is enabled"| sed -${E} "s,enabled,${SED_RED_YELLOW},"
        else
            echo "Privilege Mode is disabled"| sed -${E} "s,disabled,${SED_GREEN},"
        fi
    else
        echo_not_found
    fi
    echo ""

    print_2title "Interesting Files Mounted"
    (mount -l || cat /proc/self/mountinfo || cat /proc/1/mountinfo || cat /proc/mounts || cat /proc/self/mounts || cat /proc/1/mounts )2>/dev/null | grep -Ev "$GREP_IGNORE_MOUNTS" | sed -${E} "s,.sock,${SED_RED}," | sed -${E} "s,docker.sock,${SED_RED_YELLOW}," | sed -${E} "s,/dev/,${SED_RED},g"
    echo ""

    print_2title "Possible Entrypoints"
    ls -lah /*.sh /*entrypoint* /**/entrypoint* /**/*.sh /deploy* 2>/dev/null | sort | uniq
    echo ""
fi
