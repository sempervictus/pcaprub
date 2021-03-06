#!/usr/bin/env ruby

base = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
$:.unshift(File.join(File.dirname(base)))

require 'test/unit'
require 'pcaprub'

def log(msg)
  # Uncomment following line to print debug log messages:
  #puts msg
end

def ipv4_dev
  @ipv4_dev ||= Pcap.interfaces.find do |iface|
    Pcap.addresses(iface).any? do |family, values|
      if family == Pcap::AF_INET
        values.any? do |val|
          val.has_key?('addr') &&
            !val['addr'].empty? &&
            !(val['addr'] =~ /^(127|0)\./)
        end
      else
        false
      end
    end
  end
end

#
# Simple unit test, requires r00t.
#

class Pcap::UnitTest < Test::Unit::TestCase
  def test_version
    assert_equal(String, Pcap.version.class)
    log "Pcaprub version: #{Pcap.version}"
  end

  def test_lookupdev
    assert_equal(String, Pcap.lookupdev.class)
    log "Pcaprub default device: #{Pcap.lookupdev}"
  end

  def test_lookupnet
    dev = ipv4_dev
    assert_equal(String, dev.class, "Cannot find IPv4 device")
    net = Pcap.lookupnet(dev)
    assert_equal(Array, net.class)
    log "Pcaprub net (#{dev}): #{net[0]} #{[net[1]].pack("N").unpack("H*")[0]}"
  end

  def test_pcap_new
    o = Pcap.new
    assert_equal(Pcap, o.class)
  end

  def test_pcap_setfilter_bad
    e = nil
    o = Pcap.new
    begin
      o.setfilter("not ip")
    rescue ::Exception => e
    end

    assert_equal(e.class, PCAPRUB::PCAPRUBError)
  end

  def test_pcap_setfilter
    d = ipv4_dev
    assert_equal(String, d.class, "Cannot find IPv4 device")
    o = Pcap.open_live(d, 65535, true, 1)
    r = o.setfilter("not ip")
    assert_equal(Pcap, r.class)
  end

  def test_pcap_inject
    d = Pcap.lookupdev
    o = Pcap.open_live(d, 65535, true, 1)
    r = o.inject("X" * 512)

    # Travis CI's virtual network interface does not support injection
    if ENV['CI']
      assert_equal(-1,r)
    else
      assert_equal(512, r)
    end
  end

  def test_pcap_datalink
    d = Pcap.lookupdev
    o = Pcap.open_live(d, 65535, true, 1)
    r = o.datalink
    assert_equal(Fixnum, r.class)
  end

  def test_pcap_snapshot
    d = Pcap.lookupdev
    o = Pcap.open_live(d, 1344, true, 1)
    r = o.snapshot
    assert_equal(1344, r)
  end

  def test_pcap_stats
    d = Pcap.lookupdev
    o = Pcap.open_live(d, 1344, true, 1)
    r = o.stats
    assert_equal(Hash, r.class)
  end

  def test_pcap_next
    d = ipv4_dev
    assert_equal(String, d.class, "Cannot find IPv4 device")
    o = Pcap.open_live(d, 1344, true, 1)

    @c = 0
    t = Thread.new { while(true); @c += 1; select(nil, nil, nil, 0.10); end; }

    pkt_count = 0
    require 'timeout'
    begin
      Timeout.timeout(10) do
        o.each do |pkt|
          pkt_count += 1
        end
      end
    rescue ::Timeout::Error
    end

    t.kill
    log "Background thread ticked #{@c} times while capture was running"
    log "Captured #{pkt_count} packets"
    assert(90 < @c && @c < 110, "Background thread should tick about 100 times, got: #{@c}");
    true
  end

  def test_create_from_primitives
    d = ipv4_dev
    assert_equal(String, d.class, "Cannot find IPv4 device")
    o = Pcap.create(d).setsnaplen(65535).settimeout(100).setpromisc(true)
    assert_equal(o, o.activate)
    o.close
  end

  def test_monitor
    return if RUBY_PLATFORM =~ /mingw|win/
    d = Pcap.lookupdev
    o = Pcap.create(d)
    assert_equal(o, o.setmonitor(true))
  end

  def test_netifaces_constants
    log "AF_LINK Value is #{Pcap::AF_LINK}"
    assert_equal(Fixnum, Pcap::AF_LINK.class)
    log "AF_INET Value is #{Pcap::AF_INET}"
    assert_equal(Fixnum, Pcap::AF_INET.class)
    log "AF_INET6 Value is #{Pcap::AF_INET6}" if Pcap.const_defined?(:AF_INET6)
    assert_equal(Fixnum, Pcap::AF_INET6.class) if Pcap.const_defined?(:AF_INET6)
  end

  def test_netifaces_functions
    mac = /^([\da-fA-F]{2}:){5}[\da-fA-F]{2}$/
    ipv4 = /^(\d{1,3}\.){3}\d{1,3}$/
    ipv6 = /:[\da-fA-F]/
    Pcap.interfaces.sort.each do |iface|
      log "#{iface} :"
      assert_equal(String, iface.class)
      Pcap.addresses(iface).sort.each do |family,values|
        log "\t#{family} :"
        assert_equal(Fixnum, family.class)
        values.each do |val|
          log "\t\taddr : #{val['addr']}" if val.has_key?("addr")
          log "\t\tnetmask : #{val['netmask']}" if val.has_key?("netmask")
          log "\t\tbroadcast : #{val['broadcast']}" if val.has_key?("broadcast")
          log "\n"
          case family
          when Pcap::AF_LINK
            assert_match(mac, val['addr']) if val.has_key?('addr') && !val['addr'].empty?
          when Pcap::AF_INET
            assert_match(ipv4, val['addr']) if val.has_key?('addr') && !val['addr'].empty?
            assert_match(ipv4, val['netmask']) if val.has_key?('netmask') && !val['netmask'].empty?
            assert_match(ipv4, val['broadcast']) if val.has_key?('broadcast') && !val['broadcast'].empty?
          when Pcap::AF_INET6
            assert_match(ipv6, val['addr']) if val.has_key?('addr') && !val['addr'].empty?
            assert_match(ipv6, val['netmask']) if val.has_key?('netmask') && !val['netmask'].empty?
          end
        end
      end
    end
  end
end
