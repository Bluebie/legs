# Legs take you places, a networking companion
['rubygems', 'socket', 'thread'].each { |i| require i }
require 'json' unless self.class.const_defined? 'JSON'

class Legs
  # general getters
  attr_reader :socket, :parent, :meta
  def inspect; "<Legs:#{object_id} Meta: #{@meta.inspect}>"; end
  
  # Legs.new for a client, subclass to make a server, .new then makes server and client!
  def initialize(host = 'localhost', port = 30274)
    self.class.start(port) if self.class != Legs && !self.class.started?
    ObjectSpace.define_finalizer(self) { self.close! }
    @parent = false; @responses = Hash.new; @meta = {}; @disconnected = false
    @responses_mutex = Mutex.new; @socket_mutex = Mutex.new
    
    if host.instance_of?(TCPSocket)
      @socket = host
      @parent = port unless port.instance_of?(Numeric)
    elsif host.instance_of?(String)
      @socket = TCPSocket.new(host, port)
      self.class.outgoing_mutex.synchronize { self.class.outgoing.push self }
    else
      raise "First argument needs to be a hostname, ip, or socket"
    end
    
    
    @handle_data = Proc.new do |data|
      data = json_restore(JSON.parse(data))
      
      if data['method']
        (@parent || self.class).__data!(data, self)
      elsif data['error'] and data['id'].nil?
        raise data['error']
      else
        @responses_mutex.synchronize { @responses[data['id']] = data }
      end
    end
    
    @thread = Thread.new do
      until @socket.closed?
        begin
          close! if @socket.eof?
          data = nil
          @socket_mutex.synchronize { data = @socket.gets(self.class.terminator) rescue nil }
          if data.nil?
            close!
          else
            @handle_data[data]
          end
        rescue JSON::ParserError => e
          send_data!({"error" => "JSON provided is invalid. See http://json.org/ to see how to format correctly."})
        rescue IOError => e
          close!
        end
      end
    end
  end
  
  # I think you can guess this one
  def connected?; self.class.connections.include?(self); end
  
  # closes the connection and the threads and stuff for this user
  def close!
    return if @disconnected == true
    
    @disconnected = true
    puts "User #{inspect} disconnecting" if self.class.log?
    
    # notify the remote side
    notify!('**remote__disconnecting**') rescue nil
    
    if @parent
      @parent.event(:disconnect, self)
      @parent.incoming_mutex.synchronize { @parent.incoming.delete(self) }
    else
      self.class.outgoing_mutex.synchronize { self.class.outgoing.delete(self) }
    end
    
    #Thread.new { sleep(1); @socket.close rescue nil }
    @socket.close
  end
  
  # send a notification to this user
  def notify!(method, *args, &blk)
    puts "Notify #{inspect}: #{method}(#{args.map(&:inspect).join(', ')})" if self.class.log?
    send_data!({'method' => method.to_s, 'params' => args, 'id' => nil})
  end
  
  # sends a normal RPC request that has a response
  def send!(method, *args, &blk)
    puts "Call #{self.inspect}: #{method}(#{args.map(&:inspect).join(', ')})" if self.class.log?
    id = get_unique_number
    send_data! 'method' => method.to_s, 'params' => args, 'id' => id
    
    worker = Proc.new do
      sleep 0.1 until @responses_mutex.synchronize { @responses.keys.include?(id) }
      
      result = Legs::Result.new(@responses_mutex.synchronize { @responses.delete(id) })
      puts ">> #{method} #=> #{result.data['result'].inspect}" if self.class.log?
      result
    end
    
    if blk.respond_to?(:call); Thread.new { blk[worker.call] }
    else; worker.call.value; end
  end
  
  # catch all the rogue calls and make them work niftily
  alias_method :method_missing, :send!
  
  # sends raw object over the socket
  def send_data!(data)
    raise "Lost remote connection" unless connected?
    raw = JSON.generate(json_marshal(data)) + self.class.terminator
    @socket_mutex.synchronize { @socket.write(raw) }
  end
  
  
  private
  
  # takes a ruby object, and converts it if needed in to marshalled hashes
  def json_marshal(object)
    case object
    when Bignum, Fixnum, Integer, Float, TrueClass, FalseClass, String, NilClass
      return object
    when Hash
      out = Hash.new
      object.each_pair { |k,v| out[k.to_s] = json_marshal(v) }
      return out
    when Array
      return object.map { |v| json_marshal(v) }
    when Symbol
      return {'__jsonclass__' => ['Legs', '__make_symbol', object.to_s]}
    when Exception
      return {'__jsonclass__' => ['Legs::RemoteError', 'new', "<#{object.class.name}> #{object.message}", object.backtrace]}
    else
      return {'__jsonclass__' => [object.class.name, '_load', object._dump]} if object.respond_to?(:_dump)
      
      # the default marshalling behaviour
      instance_vars = {}
      object.instance_variables.each do |var_name|
        instance_vars[var_name.to_s.sub(/@/, '')] = json_marshal(object.instance_variable_get(var_name))
      end
      
      return {'__jsonclass__' => [object.class.name, 'new']}.merge(instance_vars)
    end
  end
  
  SAFE_CONSTRUCTORS = ['new', 'allocate', '_load']
  
  # takes an object from the network, and decodes any marshalled hashes back in to ruby objects
  def json_restore(object)
    case object
    when Hash
      if object.keys.include? '__jsonclass__'
        constructor = object.delete('__jsonclass__')
        class_name = constructor.shift.to_s
        
        # find the constant through the heirachy
        object_class = Module
        class_name.split(/::/).each { |piece_of_const| object_class = object_class.const_get(piece_of_const) } rescue false
        
        if object_class
          unless constructor.empty?
            raise "Unsafe marshaling constructor method: #{constructor.first}" unless (object_class == Legs and constructor.first =~ /^__make_/) or SAFE_CONSTRUCTORS.include?(constructor.first)
            raise "#{class_name} doesn't support the #{constructor.first} constructor" unless object_class.respond_to?(constructor.first)
            instance = object_class.__send__(*constructor)
          else
            instance = object_class.allocate
          end
          
          object.each_pair do |key, value|
            instance.instance_variable_set("@#{key}", json_restore(value))
          end
          return instance
        else
          raise "Response contains a #{class_name} but that class is not loaded locally, it needs to be."
        end
      else
        hash = Hash.new
        object.each_pair { |k,v| hash[k] = json_restore(v) }
        return hash
      end
    when Array
      return object.map { |i| json_restore(i) }
    else
      return object
    end
  end
  
  # gets a unique number that we can use to match requests to responses
  def get_unique_number; @unique_id ||= 0; @unique_id += 1; end
end

# undef's the superclass's methods so they won't get in the way
removal_list = Legs.instance_methods(true).map { |i| i.to_s }
removal_list -= %w{JSON new class object_id send __send__ __id__ < <= <=> => > == === yield raise}
removal_list -= Legs.instance_methods(false).map { |i| i.to_s }
Legs.class_eval { removal_list.each { |m| undef_method m } }


# the server is started by subclassing Legs, then SubclassName.start
class << Legs
  attr_accessor :terminator, :log
  attr_reader :incoming, :outgoing, :server_object, :incoming_mutex, :outgoing_mutex, :messages_mutex
  alias_method :log?, :log
  alias_method :users, :incoming
  def started?; @started; end
  
  def initializer
    ObjectSpace.define_finalizer(self) { self.stop! }
    @incoming = []; @outgoing = []; @messages = Queue.new; @terminator = "\n"; @log = false
    @incoming_mutex = Mutex.new; @outgoing_mutex = Mutex.new; @started = false
  end
  
  
  # starts the server, pass nil for port to make a 'server' that doesn't actually accept connections
  # This is useful for adding methods to Legs so that systems you connect to can call methods back on you
  def start(port=30274, &blk)
    return @server_class.module_eval(&blk) if started? and blk.respond_to? :call
    @started = true
    
    # makes a nice clean class to hold all the server methods.
    if @server_class.nil?
      @server_class = Class.new
      @server_class.module_eval do
        private
        attr_reader :server, :caller
        
        # sends a notification message to all connected clients
        def broadcast(*args)
          if args.first.is_a?(Array)
            list = args.shift
            method = args.shift
          elsif args.first.is_a?(String) or args.first.is_a?(Symbol)
            list = server.incoming
            method = args.shift
          else
            raise "You need to specify a 'method' to broadcast out to"
          end
          
          list.each { |user| user.notify!(method, *args) }
        end
        
        # Finds a user by the value of a certain property... like find_user_by :object_id, 12345
        def find_user_by_object_id value
          server.incoming.find { |user| user.object_id == value }
        end
        
        # finds user's with the specified meta keys matching the specified values, can use regexps and stuff, like a case block
        def find_users_by_meta hash = nil
          raise "You need to give find_users_by_meta a hash to check the user's meta hash against" if hash.nil?
          server.incoming.select do |user|
            hash.all? { |key, value| value === user.meta[key] }
          end
        end
        
        public # makes it public again for the user code
      end
    end
    
    @server_class.module_eval(&blk) if blk.respond_to?(:call)
    
    if @server_object.nil?
      @server_object = @server_class.allocate
      @server_object.instance_variable_set(:@server, self)
      @server_object.instance_eval { initialize }
    end
  
    @message_processor = Thread.new do
      while started?
        sleep 0.01 while @messages.empty?
        data, from = @messages.deq
        method = data['method']; params = data['params']
        methods = @server_object.public_methods(false).map { |i| i.to_s }
        
        # close dead connections
        if data['method'] == '**remote__disconnecting**'
          from.close!
          next
        else
          begin
            raise "Supplied method is not a String" unless method.is_a?(String)
            raise "Supplied params object is not an Array" unless params.is_a?(Array)
            raise "Cannot run '#{method}' because it is not defined in this server" unless methods.include?(method.to_s) or methods.include? :method_missing
            
            puts "Call #{method}(#{params.map(&:inspect).join(', ')})" if log?
            
            @server_object.instance_variable_set(:@caller, from)
            
            result = nil
            
            @incoming_mutex.synchronize do
              if methods.include?(method.to_s)
                result = @server_object.__send__(method.to_s, *params)
              else
                result = @server_object.method_missing(method.to_s, *params)
              end
            end
            
            puts ">> #{method} #=> #{result.inspect}" if log?
            
            from.send_data!({'id' => data['id'], 'result' => result}) unless data['id'].nil?
            
          rescue Exception => e
            from.send_data!({'error' => e, 'id' => data['id']}) unless data['id'].nil?
            puts "Error: #{e}\nBacktrace: " + e.backtrace.join("\n   ") if log?
          end
        end
      end
    end unless @message_processor and @message_processor.alive?
    
    if ( port.nil? or port == false ) == false and @listener.nil?
      @listener = TCPServer.new(port)
      
      @acceptor_thread = Thread.new do
        while started?
          user = Legs.new(@listener.accept, self)
          @incoming_mutex.synchronize { @incoming.push user }
          puts "User #{user.object_id} connected, number of users: #{@incoming.length}" if log?
          self.event :connect, user
        end
      end
    end
  end
  
  # stops the server, disconnects the clients
  def stop
    @started = false
    @incoming.each { |user| user.close! }
  end
  
  # returns an array of all connections
  def connections
    @incoming + @outgoing
  end
  
  # add an event call to the server's message queue
  def event(name, sender, *extras)
    return unless @server_object.respond_to?("on_#{name}")
    __data!({'method' => "on_#{name}", 'params' => extras.to_a, 'id' => nil}, sender)
  end
  
  # gets called to handle all incoming messages (RPC requests)
  def __data!(data, from)
    @messages.enq [data, from]
  end
  
  # People say this syntax is too funny not to have... whatever. Works like IO and File and what have you
  def open(*args)
    client = Legs.new(*args)
    yield(client)
    client.close!
  end
  
  # add's a method to the 'server' class, bound in to that class
  def define_method(name, &blk); @server_class.class_eval { define_method(name, &blk) }; end
  
  # add's a block to the 'server' class in a way that retains it's old bindings.
  # the block will be passed the caller object, followed by the args.
  def add_block(name, &block)
    @server_class.class_eval do
      define_method(name) do |*args|
        block.call caller, *args
      end
    end
  end
  
  # lets the marshaler transport symbols
  def __make_symbol(name); name.to_sym; end
  
  # hooks up these methods so you can use them off the main object too!
  [:broadcast, :find_user_by_object_id, :find_users_by_meta].each do |name|
    define_method name do |*args|
      @incoming_mutex.synchronize do; @outgoing_mutex.synchronize do
        @server_object.__send__(name, *args)
      end; end
    end
  end
end

Legs.initializer

# represents the data response, handles throwing of errors and stuff
class Legs::Result
  attr_reader :data
  def initialize(data); @data = data; end
  def result
    unless @data['error'].nil? or @errored
      @errored = true
      raise @data['error']
    end
    @data['result']
  end
  alias_method :value, :result
end

class Legs::StartBlockError < StandardError; end
class Legs::RequestError < StandardError; end
class Legs::RemoteError < StandardError
  def initialize(msg, backtrace)
    super(msg)
    set_backtrace(backtrace)
  end
end
