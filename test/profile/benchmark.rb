
HERE = File.expand_path('..', __FILE__)
$LOAD_PATH << File.expand_path('../../lib', HERE) << File.expand_path('..', HERE)
UNIX_SOCKET_NAME = File.join(ENV['TMPDIR']||'/tmp','memcached')

require 'benchmark'
require 'rubygems'
require 'ruby-debug' if ENV['DEBUG']
begin; require 'memory'; rescue LoadError; end

puts `uname -a`
puts "#{RUBY_ENGINE} #{RUBY_VERSION}p#{RUBY_PATCHLEVEL}"

class Bench

  def initialize(loops = nil, stack_depth = nil)
    @loops = (loops || 20000).to_i
    @stack_depth = (stack_depth || 0).to_i
    
    puts "Loops is #{@loops}"
    puts "Stack depth is #{@stack_depth}"
        
    @m_value = Marshal.dump(
      @small_value = ["testing"])    
    @m_large_value = Marshal.dump(
      @large_value = [{"test" => "1", "test2" => "2", Object.new => "3", 4 => 4, "test5" => 2**65}] * 2048)

    puts "Small value size is: #{@m_value.size} bytes"
    puts "Large value size is: #{@m_large_value.size} bytes"

    @keys = [
      @k1 = "Short",
      @k2 = "Sym1-2-3::45" * 8,
      @k3 = "Long" * 40,
      @k4 = "Medium" * 8,
      @k5 = "Medium2" * 8,
      @k6 = "Long3" * 40]
    
    reset_servers
    reset_clients
    
    Benchmark.bm(36) do |x| 
      @benchmark = x 
    end
  end

  def run(level = @stack_depth)
    level > 0 ? run(level - 1) : run_without_recursion
  end
  
  private
  
  def reset_servers
    system("ruby #{HERE}/../setup.rb")
    sleep(1)
  end

  def try_load(*loaders)
    loaders.each do |loader|
      begin
        loader.call
      rescue Exception => e
        puts e.to_s
      end
    end
  end

  def reset_clients
    @clients = {}
    loaders =  [lambda do
                  require 'memcached'
                  @clients.update({
                   "libm:ascii" => Memcached::Rails.new(
                     ['127.0.0.1:43042', '127.0.0.1:43043'],
                     :buffer_requests => false, :no_block => false, :namespace => "namespace"),
                   "libm:ascii:pipeline" => Memcached::Rails.new(
                     ['127.0.0.1:43042', '127.0.0.1:43043'],
                     :no_block => true, :buffer_requests => true, :noreply => true, :namespace => "namespace"),
                   "libm:ascii:udp" => Memcached::Rails.new(
                     ["#{UNIX_SOCKET_NAME}0", "#{UNIX_SOCKET_NAME}1"],
                     :buffer_requests => false, :no_block => false, :namespace => "namespace"),
                   "libm:bin" => Memcached::Rails.new(
                     ['127.0.0.1:43042', '127.0.0.1:43043'],
                     :buffer_requests => false, :no_block => false, :namespace => "namespace", :binary_protocol => true),
                   "libm:bin:buffer" => Memcached::Rails.new(
                     ['127.0.0.1:43042', '127.0.0.1:43043'],
                     :no_block => true, :buffer_requests => true, :namespace => "namespace", :binary_protocol => true)
                  })
                end,
                lambda do
                  require 'remix_compat'
                  Remix::Stash.set_clusters({:default => Remix::Stash::Cluster.new(['127.0.0.1:43042', '127.0.0.1:43043'])})
                end,
                lambda do
                  gem 'jruby-memcache-client'
                  require 'memcache'
                  @clients.update({"jmclient:ascii" => MemCache.new(['127.0.0.1:43042', '127.0.0.1:43043'])})
                end,
                lambda do
                  require 'spy_compat'
                  @clients.update({"spym" => Spymemcached::ClientCompat.new(['127.0.0.1:43042', '127.0.0.1:43043'])})
                end,
                lambda do
                  return if defined?(::MemCache)
                  require 'memcache'
                  @clients.update({"mclient:ascii" => MemCache.new(['127.0.0.1:43042', '127.0.0.1:43043'])})
                end,
                lambda do
                  require 'dalli_compat'
                  @clients.update({"dalli:bin" => Dalli::ClientCompat.new(['127.0.0.1:43042', '127.0.0.1:43043'], :marshal => false, :threadsafe => false)})
                end
               ]
    try_load(*loaders)
  end
  
  
  def benchmark_clients(test_name, clients = @clients)
    clients.keys.sort.each do |client_name|
      next if client_name == "stash" and test_name == "set-large" # Don't let stash break the world
      client = clients[client_name]
      begin
        yield client
        @benchmark.report("#{test_name}: #{client_name}") { @loops.times { yield client } }
      rescue => e
        puts "#{test_name}:#{client_name} => #{e.inspect}"
        # reset_clients
      end
    end
    puts
  end
  
  def benchmark_hashes(hashes, test_name)
    hashes.each do |hash_name, int|
      @m = Memcached::Rails.new(:hash => hash_name)
      @benchmark.report("#{test_name}:#{hash_name}") do
        (@loops * 5).times { yield int }
      end
    end  
  end
  
  def run_without_recursion
    benchmark_clients("set") do |c|
      c.set @k1, @m_value, 0, true
      c.set @k2, @m_value, 0, true
      c.set @k3, @m_value, 0, true
    end

    benchmark_clients("get") do |c|
      c.get @k1, true
      c.get @k2, true
      c.get @k3, true
    end
    
    benchmark_clients("get-multi") do |c|
      c.get_multi @keys, true
    end
    
    benchmark_clients("append") do |c|
      c.append @k1, @m_value
      c.append @k2, @m_value
      c.append @k3, @m_value
    end    

    benchmark_clients("prepend") do |c|
      c.prepend @k1, @m_value
      c.prepend @k2, @m_value
      c.prepend @k3, @m_value
    end       
  
    benchmark_clients("delete") do |c|    
      c.delete @k1
      c.delete @k2
      c.delete @k3
    end
    
    benchmark_clients("get-missing") do |c|
      c.get @k1
      c.get @k2
      c.get @k3
    end

    benchmark_clients("append-missing") do |c|
      c.append @k1, @m_value
      c.append @k2, @m_value
      c.append @k3, @m_value
    end

    benchmark_clients("prepend-missing") do |c|
      c.prepend @k1, @m_value
      c.prepend @k2, @m_value
      c.prepend @k3, @m_value
    end
    
    benchmark_clients("set-large") do |c|
      c.set @k1, @m_large_value, 0, true
      c.set @k2, @m_large_value, 0, true
      c.set @k3, @m_large_value, 0, true
    end

    benchmark_clients("get-large") do |c|
      c.get @k1, true
      c.get @k2, true
      c.get @k3, true
    end
     
    benchmark_hashes(Memcached::HASH_VALUES, "hash") do |i|
      Rlibmemcached.memcached_generate_hash_rvalue(@k1, i)
      Rlibmemcached.memcached_generate_hash_rvalue(@k2, i)
      Rlibmemcached.memcached_generate_hash_rvalue(@k3, i)
      Rlibmemcached.memcached_generate_hash_rvalue(@k4, i)
      Rlibmemcached.memcached_generate_hash_rvalue(@k5, i)
      Rlibmemcached.memcached_generate_hash_rvalue(@k6, i)    
    end if defined?(Memcached::HASH_VALUES)
  end
end

Bench.new(ENV["LOOPS"], ENV["STACK_DEPTH"]).run

Process.memory.each do |key, value|
  puts "#{key}: #{value/1024.0}M"
end if Process.respond_to? :memory
