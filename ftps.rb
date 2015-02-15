require 'net/ftp'
require 'thread'
require 'optparse'
require 'io/console'

class ConTimer
  attr_accessor :timeout
  
  def initialize(timeout)
    @timeout = timeout
    @mutex = Mutex.new
    @running = false
  end
  
  def tick
    @mutex.synchronize {@running = true}
    @tmr = Thread.new do
      sleep @timeout
      @mutex.synchronize {@running = false}
    end
  end
  
  def expired?
    not @running
  end
  
  def reset
    self.stop
    self.tick
  end
  
  def stop
    if not self.expired?
      @tmr.kill
      @tmr = nil
      @mutex.synchronize {@running = false}
    end
  end
end

class CommandParser
  @@cmds = ["pwd", "cd", "ls", "put", "help",
            "get", "mput", "mget", "reconnect"]

  def self.cmds
    @@cmds
  end

  def parse(line)
    parts = line.split(/\s+/)
    if parts.length > 0
      cmd = parts[0].downcase
      args = []
      if parts.length > 1
        args = parts[1..-1]
      end
      if @@cmds.include?(cmd)
        # valid command
        cmd = cmd.to_sym
      else
        cmd = :bad
      end
      [cmd, args]
    else
      [:bad, nil]
    end
  end
end
  

class Context
  def initialize(host, uname, passwd)
    @uname = uname
    @passwd = passwd
    @host = host
    @last_dir = nil
    @tmr = nil
  end
  
  def connect
    begin
      @ftp = Net::FTP.new(@host)
      @ftp.login(@uname, @passwd) 
    rescue Exception => ex
      puts "Exception happened: #{ex}"
      puts "Aborting..."
      exit 1
    end
    if @tmr == nil
      @tmr = ConTimer.new(60)
    end
 
    if @last_dir == nil
      @last_dir = @ftp.pwd
    else
      @ftp.chdir(@last_dir)
    end
    
    @tmr.reset
  end
  
  def disconnect
    begin
      @ftp.quit
    rescue Exception
      # okay, might have timed out already
      # just stay quiet here
      # and we will try to reconnect
    end
  end
  
  def reconnect
    self.disconnect
    self.connect
  end
  
  def command(cmd, args)
    if @tmr.expired?
      self.reconnect
    else
      @tmr.reset
    end

    args = args.join(" ")

    case cmd
    when :ls
      begin
        r = @ftp.list(args)
        r.each {|f| puts f}
      rescue Exception => ex
        puts "Could not do that - #{ex}"
      end
    when :cd
      begin
        @ftp.chdir(args)
        r = @ftp.pwd
        @last_dir = r
        puts "PWD = #{r}"
      rescue Exception => ex
        puts "Cannot change directory to #{args} -  #{ex}"
      end
    when :pwd
      puts "PWD = #@last_dir"
    when :get, :put
      begin
        @ftp.send(cmd, args)
      rescue Exception => ex
        puts "Cannot #{cmd.to_s.upcase} - #{ex}"
      end
    when :mget
      begin
        files = @ftp.list(args).map {|f| f.split(/\s+/)[-1]}
        if files.length > 0
          files.each do |f|
            puts "\tgetting #{f}"
            @ftp.get(f)
          end
        end
      rescue Exception => ex
        puts "MGET failed - #{ex}"
      end
    when :mput
      begin
        files = Dir.glob(args)
        if files.length > 0
          files.each do |f|
            puts "\tputting #{f}"
            @ftp.put(f)
          end
        end
      rescue Exception => ex
        puts "MPUT failed - #{ex}"
      end
    when :help
      puts CommandParser.cmds.join(" ")
    when :reconnect
      self.reconnect
      puts "Reconnect done"
    end
  end

  def destroy
    @tmr.stop
    #self.disconnect
  end
end

class Repl
  def self.repl(ctx)
    parser = CommandParser.new
    ctx.connect
    loop do
      print ">> "
      input = STDIN.gets
      if input =~ /(quit)|(exit)/i
        break
      end
      parse_results = parser.parse(input)
      if parse_results[0] == :bad
        puts "Bad command"
        puts "Please provide one of: #{CommandParser.cmds.join(', ')}"
      else
        ctx.command(parse_results[0], 
                    parse_results[1])
      end
    end
    puts "Quit"
    ctx.destroy
  end
end

# MAIN

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ftps [options] ftp-host"

  opts.on("-h", "--help") do |h|
    options[:help] = h
  end

  opts.on("-u", "--user u") do |u|
    options[:user] = u
  end

  opts.on("-p", "--password p") do |p|
    options[:pass] = p
  end
end.parse!

user = ""
pass = ""

if ARGV.length != 1
  puts "Usage: ftps [options] ftp-host"
  exit 1
end

if options[:help]
  puts "Help will always be given to those who deserve it!"
  exit 0
end

if options[:user]
  user = options[:user]
else
  print "Please enter a username: "
  user = STDIN.gets
end

if options[:pass]
  pass = options[:pass]
else
  print "Please enter your password: "
  STDIN.echo = false
  pass = STDIN.gets
  STDIN.echo = true
  puts ""
end

host = ARGV[0]

Repl.repl(Context.new(host, user.chomp, pass.chomp))

    
