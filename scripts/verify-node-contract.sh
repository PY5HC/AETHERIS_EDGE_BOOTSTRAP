#!/usr/bin/env bash
set -u
RC=0; IDENTITY=/etc/aetheris/node/identity.env; CAPABILITIES=/etc/aetheris/node/capabilities.json
fail(){ echo "FAIL $*"; RC=1; }; pass(){ echo "PASS $*"; }; check_dir(){ local p=$1 o=$2 g=$3 m=$4 a; [ -d "$p" ]||{ fail "missing $p"; return; }; a=$(stat -c '%U:%G %a' "$p"); [ "$a" = "$o:$g $m" ]&&pass "$p $a"||fail "$p actual=$a expected=$o:$g $m"; }; check_file(){ local p=$1 a; [ -f "$p" ]||{ fail "missing $p"; return; }; a=$(stat -c '%U:%G %a' "$p"); [ "$a" = 'root:aetheris 640' ]&&pass "$p $a"||fail "$p actual=$a"; }
for s in '/etc/aetheris root aetheris 750' '/etc/aetheris/node root aetheris 750' '/opt/aetheris root aetheris 755' '/opt/aetheris/releases root aetheris 755' '/opt/aetheris/current root aetheris 755' '/var/lib/aetheris root aetheris 750' '/var/lib/aetheris/node root aetheris 750' '/var/log/aetheris root aetheris 750' '/run/aetheris root aetheris 755'; do read -r p o g m<<<"$s"; check_dir "$p" "$o" "$g" "$m"; done
getent group aetheris >/dev/null 2>&1&&pass 'group aetheris'||fail 'group aetheris'; check_file "$IDENTITY"; check_file "$CAPABILITIES"
[ -d /opt/aetheris/current ]&&pass '/opt/aetheris/current directory v1'||fail '/opt/aetheris/current directory v1'
[ -f /usr/lib/tmpfiles.d/aetheris.conf ]&&[ "$(tr -d '\r'</usr/lib/tmpfiles.d/aetheris.conf)" = 'd /run/aetheris 0755 root aetheris -' ]&&pass 'exact tmpfiles content'||fail 'exact tmpfiles content'
discover(){ [ -r /etc/os-release ]||return 1; . /etc/os-release; [ -n "${ID:-}" ]&&[ -n "${VERSION_ID:-}" ]||return 1; D_OS=$ID-$VERSION_ID; D_HOSTNAME=$(hostname); D_MACHINE_ID=$(cat /etc/machine-id); D_ARCH=$(uname -m); D_KERNEL=$(uname -r); [ -r /etc/nv_tegra_release ]||return 1; D_L4T=$(sed -n 's/^# R\([0-9][0-9]*\).*REVISION: \([0-9.][0-9.]*\).*/\1.\2/p' /etc/nv_tegra_release|head -n1); [ -n "$D_L4T" ]||return 1; [ -r /proc/device-tree/model ]||return 1; D_MODEL=$(tr -d '\000'</proc/device-tree/model); D_ML=$(printf '%s' "$D_MODEL"|tr '[:upper:]' '[:lower:]'); [[ "$D_ML" == *jetson*orin\ nano*&&"$D_ML" == *super* ]]||return 1; D_PLATFORM=jetson-orin-nano-super; [ -x /usr/sbin/nvpmodel ]||return 1; D_NVP=$(/usr/sbin/nvpmodel -q 2>/dev/null)||return 1; D_POWER=$(printf '%s\n' "$D_NVP"|sed -n 's/^NV Power Mode:[[:space:]]*\([^[:space:]].*\)$/\1/p'|head -n1); D_POWER_ID=$(printf '%s\n' "$D_NVP"|sed -n 's/^[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p'|head -n1); [ -n "$D_POWER" ]&&[ -n "$D_POWER_ID" ]||return 1; D_BOOT_TARGET=$(systemctl get-default 2>/dev/null)||return 1; [ "$D_BOOT_TARGET" = multi-user.target ]||return 1; D_BOOT_PROFILE=headless-conservative; D_NVCC=/usr/local/cuda/bin/nvcc; [ -x "$D_NVCC" ]||D_NVCC=$(command -v nvcc 2>/dev/null||true); [ -x "$D_NVCC" ]||return 1; D_CUDA=$($D_NVCC --version 2>/dev/null|sed -n 's/.*release \([0-9.]*\).*/\1/p'|head -n1); package_version(){ dpkg-query -W -f='${Version}\n' "$1" 2>/dev/null|head -n1|cut -d- -f1|cut -d+ -f1; }; D_CUDNN=$(package_version libcudnn9-cuda-13); D_TENSORRT=$(package_version libnvinfer10); D_VPI=$(package_version libnvvpi4); D_JETPACK=$(package_version nvidia-jetpack); [ -n "$D_CUDA" ]&&[ -n "$D_CUDNN" ]&&[ -n "$D_TENSORRT" ]&&[ -n "$D_VPI" ]&&[ -n "$D_JETPACK" ]||return 1; D_CTK=$(command -v nvidia-ctk 2>/dev/null||true); [ -x "$D_CTK" ]||return 1; D_CDI=$($D_CTK cdi list 2>/dev/null)||return 1; printf '%s\n' "$D_CDI"|grep -q nvidia.com/gpu||return 1; D_DOCKER=$(command -v docker 2>/dev/null||true); [ -x "$D_DOCKER" ]&&systemctl is-active --quiet docker||return 1; }
discover&&pass 'current platform discovery'||fail 'current platform discovery'
if [ -f "$IDENTITY" ]&&[ -f "$CAPABILITIES" ]&&[ -n "${D_OS:-}" ]; then export D_OS D_HOSTNAME D_MACHINE_ID D_ARCH D_KERNEL D_L4T D_PLATFORM D_POWER D_BOOT_PROFILE D_CUDA D_CUDNN D_TENSORRT D_VPI D_JETPACK; if python3 - "$IDENTITY" "$CAPABILITIES" <<'PY2'
import json,os,sys
ip,cp=sys.argv[1:]; keys='AETHERIS_NODE_ID AETHERIS_NODE_ROLE AETHERIS_NODE_CLASS AETHERIS_PLATFORM AETHERIS_HOSTNAME AETHERIS_MACHINE_ID AETHERIS_ARCH AETHERIS_KERNEL AETHERIS_OS AETHERIS_L4T_RELEASE AETHERIS_JETPACK_RELEASE AETHERIS_POWER_PROFILE AETHERIS_BOOT_PROFILE'.split(); vals={}
for line in open(ip):
 line=line.rstrip('\n')
 if not line: continue
 if '=' not in line: raise SystemExit('malformed identity')
 k,v=line.split('=',1)
 if k in vals: raise SystemExit('duplicate identity key')
 vals[k]=v
if set(vals)!=set(keys) or any(not vals[k] or '{{' in vals[k] or '}}' in vals[k] for k in keys): raise SystemExit('identity key/value mismatch')
obs={'AETHERIS_HOSTNAME':'D_HOSTNAME','AETHERIS_MACHINE_ID':'D_MACHINE_ID','AETHERIS_ARCH':'D_ARCH','AETHERIS_KERNEL':'D_KERNEL','AETHERIS_OS':'D_OS','AETHERIS_L4T_RELEASE':'D_L4T','AETHERIS_JETPACK_RELEASE':'D_JETPACK','AETHERIS_POWER_PROFILE':'D_POWER','AETHERIS_BOOT_PROFILE':'D_BOOT_PROFILE','AETHERIS_PLATFORM':'D_PLATFORM'}
if any(vals[k]!=os.environ[e] for k,e in obs.items()) or vals['AETHERIS_NODE_CLASS']!='jetson' or vals['AETHERIS_ARCH']!='aarch64': raise SystemExit('observed identity mismatch')
d=json.load(open(cp)); p=d.get('platform',{}); c=d.get('capabilities',{})
if d.get('schema_version')!='1.0' or d.get('node_id')!=vals['AETHERIS_NODE_ID'] or d.get('node_role')!=vals['AETHERIS_NODE_ROLE'] or p!={'family':'nvidia-jetson','model':vals['AETHERIS_PLATFORM'],'architecture':vals['AETHERIS_ARCH']}: raise SystemExit('capability identity/platform mismatch')
for n,e in [('cuda','D_CUDA'),('cudnn','D_CUDNN'),('tensorrt','D_TENSORRT'),('vpi','D_VPI')]:
 if c.get(n,{}).get('available') is not True or c[n].get('version')!=os.environ[e]: raise SystemExit(n+' mismatch')
if c.get('nvidia_container_runtime')!={'available':True,'cdi':True} or c.get('docker')!={'available':True,'rootless':False}: raise SystemExit('host capability mismatch')
for n in ('node_agent','sky','rf','local_ai'):
 if c.get(n)!={'available':False,'state':'not_installed'}: raise SystemExit(n+' mismatch')
print('semantic verifier passed')
PY2
then pass 'semantic identity/capability validation'; else fail 'semantic identity/capability validation'; fi; else fail 'semantic files/discovery unavailable'; fi
echo "VERIFY_RC=$RC"; exit "$RC"
