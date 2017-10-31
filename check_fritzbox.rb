#!/usr/bin/env ruby

require 'ruby_dig' if RUBY_VERSION < '2.3'

require 'getoptlong'
#require 'json'
require 'easy_upnp'

def usage(s)
  $stderr.puts(s)
  $stderr.puts("Usage: #{File.basename($0)}")
  exit(2)
end

# -------------------------------------------------------------------------------------------------

class CheckFritzbox

  STATE_OK        = 0
  STATE_WARNING   = 1
  STATE_CRITICAL  = 2
  STATE_UNKNOWN   = 3
  STATE_DEPENDENT = 4

  def initialize( params = {} )
  end


  def output( params )

    status  = params.dig(:status)
    message = params.dig(:message)

    message_status = case status
      when STATE_OK
        'OK'
      when STATE_WARNING
        'WARNING'
      when STATE_CRITICAL
        'CRITICAL'
      else
        'UNKNOWN'
    end

    puts format( '%s - %s', message_status,  message )
    exit status
  end



  def upnp_data()

    searcher = EasyUpnp::SsdpSearcher.new( timeout: 1 )
    devices = searcher.search('ssdp:all')

    device = devices.select { |x| x.device_name =~ /WANDevice/ }

    whitelist = %w(GetCommonLinkProperties GetTotalBytesSent GetTotalBytesReceived GetTotalPacketsSent GetTotalPacketsReceived GetAddonInfos GetDSLLinkInfo GetStatusInfo GetExternalIPAddress)

    array = []

    device.each do |d|

      %w(WANCommonInterfaceConfig WANDSLLinkConfig WANIPConnection).each do |x|

        schema = format('urn:schemas-upnp-org:service:%s:1', x)

        service = d.service(schema) do |s|
          s.log_enabled = false
          s.log_level = :info
          s.validate_arguments = true
        end

        unless service.nil?

          methods = service.service_methods

          next if methods.nil?

          methods.each do |m|

            if( whitelist.include?(m.to_s) )

              i = service.method(m.to_sym)

              begin
                array << i.call
              rescue => e
                puts e
              end
            end

          end

        end
      end

    end

    array.reduce( {} , :merge )
  end


  def status( data )

    connection_status = data.dig(:NewConnectionStatus)
    link_status = data.dig(:NewLinkStatus)
    physical_link_status = data.dig(:NewPhysicalLinkStatus)

    output( status: STATE_UNKNOWN, message: format( 'can\'t get connection status' ) ) if( connection_status.nil? )

    connection_status = connection_status.downcase

    output( status: STATE_OK      , message: format( 'connection up' ) ) if( connection_status == 'connected' )
    output( status: STATE_WARNING , message: format( 'connection status %s', connection_status ) ) if( connection_status == 'connecting' || connection_status == 'authenticating' )
    output( status: STATE_CRITICAL, message: format( 'connection state' ) )

  end

  def uptime( data )

    uptime = data.dig(:NewUptime)

    output( status: STATE_UNKNOWN, message: format( 'can\'t get uptime status' ) ) if( uptime.nil? )

    _time = Time.at(uptime.to_i)
    uptime_days    = 0
    uptime_days    = _time.day if( uptime.to_i >= 86400 )
    uptime_hours   = _time.hour
    uptime_minutes = _time.min

    message = format( 'uptime %s seconds (%s days, %s hours, %s minutes)', uptime, uptime_days, uptime_hours, uptime_minutes )
    performance = format( 'uptime=%s', uptime )

    output( status: STATE_OK, message: message, performance: performance ) unless( uptime.nil? )
  end

  def connection_rate( data )

    upstream_rate = data.dig(:NewLayer1UpstreamMaxBitRate)
    downstream_rate = data.dig(:NewLayer1DownstreamMaxBitRate)

    output( status: STATE_UNKNOWN, message: format( 'can\'t get upstream rate' ) ) if( upstream_rate.nil? )
    output( status: STATE_UNKNOWN, message: format( 'can\'t get downstream rate' ) ) if( downstream_rate.nil? )

    upstream_mbit = ( upstream_rate.to_f / 1000000 ).round(2)
    downstream_mbit = ( downstream_rate.to_f / 1000000 ).round(2)

    message = format( 'upstream %s MBit/s , downstream %s MBit/s', upstream_mbit, downstream_mbit )
    performance = format( 'current_upstream=%s,current_downstream=%s', upstream_rate, downstream_rate )

    output( status: STATE_OK, message: message, performance: performance )

  end

  def transfer_rate( data )

    send_rate    = data.dig(:NewPacketSendRate)
    receive_rate = data.dig(:NewPacketReceiveRate)

  end

end


# -------------------------------------------------------------------------------------------------

opts = GetoptLong.new(
  [ '--help'    , '-h', GetoptLong::NO_ARGUMENT ],
  [ '--status',         GetoptLong::NO_ARGUMENT ],
  [ '--uptime',         GetoptLong::NO_ARGUMENT ],
  [ '--connection',     GetoptLong::NO_ARGUMENT ]
)

status = false
uptime = false
connection = false

begin

  opts.quiet = false
  opts.each do |opt, arg|

    case opt
    when '--help'
      usage("Unknown option: #{ARGV[0].inspect}")
    when '--status'
      status = true
      next
    when '--uptime'
      uptime = true
      next
    when '--connection'
      connection = true
      next
    end

  end
rescue => e
  puts "Error in arguments"
  puts e.to_s

  exit 1
end



# -------------------------------------------------------------------------------------------------

p = CheckFritzbox.new

m = p.upnp_data

p.status( m ) if( status )
p.uptime( m ) if( uptime )
p.connection_rate( m ) if( connection )

# EOF


