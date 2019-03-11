# Those are just informative to show dependencies
#include "Protocol.ps1"
#include "PortRange.ps1"

class FirewallService {
    [Protocol] $Protocol
    [PortRange] $SrcPorts
    [PortRange] $DstPorts

    FirewallService([Protocol] $Protocol, [PortRange] $SrcPorts, [PortRange] $DstPorts) {
        $this.Protocol = $Protocol
        $this.SrcPorts = $SrcPorts
        $this.DstPorts = $DstPorts
    }

    [Hashtable] GetRequest() {
        $Request = @{
            protocol  = ($this.Protocol -as [String])
            src_ports = $this.SrcPorts.GetRequest()
            dst_ports = $this.DstPorts.GetRequest()
        }

        return $Request
    }

    static [FirewallService] new_TCP_Full() {
        return [FirewallService]::new([Protocol]::tcp, [PortRange]::new_Full(), [PortRange]::new_Full())
    }

    static [FirewallService] new_UDP_range([Int] $Start, [Int] $End) {
        return [FirewallService]::new([Protocol]::udp, [PortRange]::new($Start, $End), [PortRange]::new($Start, $End))
    }

    static [FirewallService] new_UDP_Full() {
        return [FirewallService]::new([Protocol]::udp, [PortRange]::new_Full(), [PortRange]::new_Full())
    }
}
