# Copyright (C) 2014 Project Hatohol
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

module Fluent
  class HatoholOutput < BufferedOutput
    Plugin.register_output("hatohol2", self)

    config_param :url, :string, :default => nil
    config_param :queue_name, :string
    config_param :tls_cert, :string, :default => nil
    config_param :tls_key, :string, :default => nil
    config_param :tls_ca_certificates, :array, :default => []
    config_param :host_key, :string, :default => "host"
    config_param :content_format, :string, :default => "%{message}"
    config_param :severity_format, :string, :default => "ERROR"

    def initialize
      super
      require "time"
      require "json"
      require "bunny"
    end

    def configure(conf)
      super
      validate_configuraiton
    end

    def start
      super
      options = {
        :tls_cert            => @tls_cert,
        :tls_key             => @tls_key,
        :tls_ca_certificates => @tls_ca_certificates,
      }
      @connection = Bunny.new(url || {}, options)
      @connection.start
      @channel = @connection.create_channel
      @queue = @channel.queue(@queue_name)

      exchange_profile
    end

    def shutdown
      super
      @connection.close
    end

    def format(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def write(chunk)
      chunk.msgpack_each do |tag, time, record|
        @queue.publish(JSON.generate(build_events(tag, time, record)),
                       :content_type => "application/json")
      end
    end

    private
    def validate_configuraiton
      if @queue_name.nil?
        raise ConfigError, "Must set queue_name"
      end
    end

    def build_events(tag, time, record)
      build_base_msg.update({
        "method"  => "updateEvents",
        "params"  => {
          "events" => [build_event(tag, time, record)]
        }
      })
    end

    private
    def build_event(tag, time, record)
      {
        "eventId"   => build_id(time),
        "time"      => build_time(time),
        "type"      => build_type,
        #"status"    => "" # This field will be optional
        "severity"  => build_severity(record),
        "hostId"    => record[@host_key],
        "hostName"  => record[@host_key],
        "brief"     => build_content(tag, time, record),
        "extendedInfo" => "",
      }
    end

    def build_base_msg
      {
        "jsonrpc" => "2.0",
        "id"      => rand(0x80000000),
      }
    end

    private
    def exchange_profile
      msg = {
        "jsonrpc" => "2.0",
        "id"      => 1,
        "method"  => "exchangeProfile",
        "params"  => {
          "procedures" => [],
          "name"       => "Fluentd Plugin"
        }
      }
      @queue.publish(JSON.generate(msg), :content_type => "application/json")
    end

    def build_id(time)
      now = Time.now
      (now.to_i * 1_000_000_000 + now.nsec).to_s
    end

    def build_type
      # TODO: is this OK ?
      "BAD"
    end

    def build_time(time)
      utc = Time.at(time).getutc
      utc.strftime("%Y%m%d%H%M%S") + sprintf(".%09d", utc.nsec)
    end

    def build_content(tag, time, record)
      parameters = {
        :tag => tag,
        :time => time,
      }
      record.each do |key, value|
        parameters[key.to_sym] = value
      end
      @content_format % parameters
    end

    def build_severity(record)
      parameters = {}
      record.each do |key, value|
        parameters[key.to_sym] = value
      end
      @severity_format % parameters
    end
  end
end
