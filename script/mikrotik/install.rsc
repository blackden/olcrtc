# RouterOS install script for olcrtc cnc on MikroTik CHR (or any RouterOS 7.8+
# with container support enabled).
#
# Usage:
#   1. Edit the :global variables below.
#   2. Upload to the device's File List (or paste into Terminal as :import).
#   3. /import file-name=install.rsc
#   4. After extraction completes, /container/start olcrtc-cnc
#
# Pre-req: /system/device-mode/update container=yes + reboot done once.
# See docs/blackden/mikrotik-chr.md for the full walkthrough.

:global OLCRTCImage           "ghcr.io/blackden/olcrtc:latest"
:global OLCRTCMode            "cnc"
:global OLCRTCCarrier         "jitsi"
:global OLCRTCTransport       "datachannel"
:global OLCRTCRoomID          ""
:global OLCRTCKey             ""
:global OLCRTCSocksPort       "8808"

# Storage / network — usually safe to keep defaults
:global OLCRTCDisk            "disk1"
:global OLCRTCVethName        "veth-olcrtc"
:global OLCRTCBridgeName      "br-cont"
:global OLCRTCVethAddr        "172.20.0.2/24"
:global OLCRTCBridgeAddr      "172.20.0.1/24"
:global OLCRTCContainerName   "olcrtc-cnc"

# ---- sanity checks -------------------------------------------------

:if ([:len $OLCRTCRoomID] = 0) do={
    :error "edit install.rsc: OLCRTCRoomID is empty"
}
:if ([:len $OLCRTCKey] != 64) do={
    :error "edit install.rsc: OLCRTCKey must be exactly 64 hex characters"
}

# ---- container global config ---------------------------------------

/container/config/set \
    registry-url=https://ghcr.io \
    tmpdir=($OLCRTCDisk . "/cont/tmp") \
    ram-high=256M

# ---- network -------------------------------------------------------

:if ([:len [/interface/veth/find name=$OLCRTCVethName]] = 0) do={
    /interface/veth/add name=$OLCRTCVethName address=$OLCRTCVethAddr gateway=([:pick $OLCRTCBridgeAddr 0 [:find $OLCRTCBridgeAddr "/"]])
}

:if ([:len [/interface/bridge/find name=$OLCRTCBridgeName]] = 0) do={
    /interface/bridge/add name=$OLCRTCBridgeName
}

:if ([:len [/ip/address/find interface=$OLCRTCBridgeName]] = 0) do={
    /ip/address/add address=$OLCRTCBridgeAddr interface=$OLCRTCBridgeName
}

:if ([:len [/interface/bridge/port/find bridge=$OLCRTCBridgeName interface=$OLCRTCVethName]] = 0) do={
    /interface/bridge/port/add bridge=$OLCRTCBridgeName interface=$OLCRTCVethName
}

/ip/firewall/nat/add chain=srcnat action=masquerade src-address=172.20.0.0/24 comment="olcrtc container egress"

# ---- env + mounts --------------------------------------------------

/container/envs/add list=ENV_OLCRTC key=OLCRTC_MODE       value=$OLCRTCMode
/container/envs/add list=ENV_OLCRTC key=OLCRTC_CARRIER    value=$OLCRTCCarrier
/container/envs/add list=ENV_OLCRTC key=OLCRTC_TRANSPORT  value=$OLCRTCTransport
/container/envs/add list=ENV_OLCRTC key=OLCRTC_ROOM_ID    value=$OLCRTCRoomID
/container/envs/add list=ENV_OLCRTC key=OLCRTC_KEY        value=$OLCRTCKey
/container/envs/add list=ENV_OLCRTC key=OLCRTC_SOCKS_HOST value="0.0.0.0"
/container/envs/add list=ENV_OLCRTC key=OLCRTC_SOCKS_PORT value=$OLCRTCSocksPort

/container/mounts/add list=MOUNT_OLCRTC \
    src=($OLCRTCDisk . "/cont/olcrtc/state") \
    dst="/var/lib/olcrtc"

# ---- container -----------------------------------------------------

/container/add \
    remote-image=$OLCRTCImage \
    interface=$OLCRTCVethName \
    root-dir=($OLCRTCDisk . "/cont/olcrtc/root") \
    envlist=ENV_OLCRTC \
    mountlists=MOUNT_OLCRTC \
    name=$OLCRTCContainerName \
    start-on-boot=yes \
    logging=yes

:log info ("olcrtc: container added — wait for /container/print to show status=stopped, then /container/start " . $OLCRTCContainerName)
