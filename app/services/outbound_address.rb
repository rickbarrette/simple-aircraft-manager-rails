# Checks where the server is about to send a request (AirTrail, webhooks):
# resolves the host and returns the address to connect to, so the name can't
# be pointed elsewhere in between. Never the server itself, link-local
# addresses (cloud metadata) or multicast; the private network only when
# allowed (admins, or hosts the admin listed).
module OutboundAddress
  class Blocked < StandardError
    attr_reader :reason # :never | :private

    def initialize(reason, host)
      @reason = reason
      super("#{host}: #{reason}")
    end
  end

  UNREACHABLE = [ IPAddr.new("0.0.0.0/8"), IPAddr.new("::/128"), IPAddr.new("224.0.0.0/4"), IPAddr.new("ff00::/8") ].freeze
  CGNAT = IPAddr.new("100.64.0.0/10") # shared address space, e.g. Tailscale

  # Host name → IP addresses (replaceable in tests, which have no DNS).
  mattr_accessor :resolver, default: ->(host) { Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address) }

  module_function

  def resolve!(host, allow_private:)
    ips = resolver.call(host).map { IPAddr.new(_1.sub(/%.*/, "")) }.uniq
    raise SocketError, "no address for #{host}" if ips.empty?
    ips.each do |ip|
      ip = ip.native # ::ffff:10.0.0.1 → 10.0.0.1
      raise Blocked.new(:never, host) if ip.loopback? || ip.link_local? || UNREACHABLE.any? { _1.include?(ip) }
      raise Blocked.new(:private, host) if (ip.private? || CGNAT.include?(ip)) && !allow_private
    end
    ips.first.to_s
  end
end
