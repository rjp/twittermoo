#! /usr/bin/env ruby

require 'rubygems'
require 'twitter'
require 'gdbm'
require 'sha1'
require 'optparse'
require 'socket'

# TODO move this to something like log4r if they have it
def log(x)
    if $options[:verbose] then
        puts *x
    end
end

$options = {
    :host => 'localhost',
    :port => nil,
    :dbfile => ENV['HOME'] + '/.twittermoo.db',
    :config => ENV['HOME'] + '/.twittermoo',
    :verbose => nil,
    :once => nil,
    :wait => 20,
    :period => 3600,
    :every => 300,
    :keyfile => nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: twittermoo.rb [-v] [-p port] [-h host] [-d dbfile] [-c config] [-o] [-w N] [-p N] [-e N] [-k file]"

  opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
    $options[:verbose] = v
  end

  opts.on("-o", "--once", "Run once and quit") do |p|
    $options[:once] = p
  end

  opts.on("-w", "--wait N", Integer, "Delay between sending messages (seconds)") do |p|
    $options[:wait] = p
  end

  opts.on("-p", "--period N", Integer, "Time period to check for new messages (seconds)") do |p|
    $options[:period] = p
  end

  opts.on("-e", "--every N", Integer, "Time period to sleep between checks (seconds, 300+)") do |p|
    $options[:every] = p
  end

  opts.on("-p", "--port N", Integer, "irccat port") do |p|
    $options[:port] = p
  end

  opts.on("-d", "--dbfile DBFILE", String, "dbfile") do |p|
    $options[:dbfile] = p
  end

  opts.on("-h", "--host HOST", String, "host") do |p|
    $options[:host] = p
  end

  opts.on("-c", "--config CONFIG", String, "config file") do |p|
    $options[:config] = p
  end

  opts.on("-k", "--key filename", String, "Shared key file") do |p|
    $options[:keyfile] = p
  end

end.parse!

if $options[:keyfile] then
    log "loading secret key from #{$options[:keyfile]}"
    begin
        $options[:secret_key] = File.open($options[:keyfile]).read.chomp
    rescue => e
        $stderr.puts "Error getting secret key from #{$options[:keyfile]}: #{e}"
        exit(1)
    end
end

def send_message(x)
    if $options[:port].nil? then
        puts "! #{x}"
    else
        begin
            # irc_cat doesn't seem to like persistent connections
            $socket = TCPSocket.new($options[:host], $options[:port])
            if $options[:secret_key] then
                x = "%/#{$options[:secret_key]}/% #{x}"
            end
            $socket.puts(x)
            $socket.close
        end
    end
end

config = YAML::load(open($options[:config]))

# allow settings of options from the config file
unless config['options'].nil? then
    config['options'].each { |k,v|
        $options[k.to_sym] = v
    }
end

# TODO add an option for OAuth
httpauth = Twitter::HTTPAuth.new(config['email'], config['password'])
twitter = Twitter::Base.new(httpauth)

already_seen = GDBM.new($options[:dbfile])

if $options[:once].nil? then
	log "B fetching current timeline and ignoring"
	twitter.friends_timeline().each do |s|
	    sha1 = SHA1.hexdigest(s.text + s.user.name)
	    xtime = Time.parse(s.created_at)
	    threshold = Time.now - $options[:period]
	    if xtime < threshold then
	        already_seen[sha1] = "s"
	    end
	end
end

prev_time = Time.now - $options[:period]
log "L entering main loop"
loop {

    log "T fetching direct messages since #{prev_time}"

    twitter.direct_messages().each do |s|
      log "D #{s.id} #{s.text}"
      xtime = Time.parse(s.created_at)
      if xtime > prev_time then
          prev_time = xtime # this is kinda lame
      end
    end

    log "T fetching current timeline"
    tl = []
    attempts = 5
    loop do
        begin
            tl = twitter.friends_timeline()
            log "Y timeline fetched successfully, #{tl.size} items"
            break
        rescue Timeout::Error, Twitter::CantConnect
            log "E $!"
            attempts = attempts - 1
            if attempts == 0 then
                log "too many failures, bailing for 120s"
                sleep 120
                attempts = 5
            else
                log "transient failure, sleeping for 30s"
                sleep 30
            end
        rescue
            raise $!
            sleep 10
        end
    end

    log "Y timeline fetched successfully, #{tl.size} items"

    tl.reverse.each do |s|
        sha1 = SHA1.hexdigest(s.text + s.user.name)
        status = already_seen[sha1]
        if status.nil? then
            log "N +/#{sha1} #{s.user.name} #{s.text[0..6]}..."
            ts = Time.parse(s.created_at)
            output = "<#{s.user.screen_name}> #{s.text} (#{ts.strftime('%Y%m%d %H%M%S')})"
            if s.text =~ /^@(\w+)\s/ then
                log "? #{$1}"
                if 1 then # twitter.friends.include?($1) then
                    log "+ #{output}"
	                if output.length > 250 then
	                    $stderr.puts "#{output[0..250]}..."
	                    exit;
	                end
                    send_message(output)
                else
                    log "- #{output}"
                end
            else
                log "+ #{output}"
                if output.length > 250 then
                    $stderr.puts "#{output[0..250]}..."
                    exit;
                end
                send_message(output)
            end
            already_seen[sha1] = "p"
            sleep $options[:wait]
        else
            if status != 'p' then
                log "O #{status}/#{sha1} #{s.user.name} #{s.text[0..6]}..."
            end
            already_seen[sha1]='p'
        end
    end

    if $options[:once].nil? then
        log "S #{Time.now}"
        sleep $options[:every]
    else
        break
    end
}
