# Legs take you places, a networking companion to Shoes
require 'rubygems'
require 'json' unless self.class.const_defined? 'JSON'
require 'socket'
require 'thread'

Thread.abort_on_exception = true # Should be able to run without this, hopefully. Helps with debugging though

class Legs
  attr_reader :socket, :parent, :meta
  
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
      data = self.__json_restore(JSON.parse(data))
      
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
          self.close! if @socket.eof?
          data = nil
          @socket_mutex.synchronize { data = @socket.gets(self.class.terminator) }
          if data.nil?
            self.close!
          else
            @handle_data[data]
          end
        rescue JSON::ParserError => e
          self.send_data!({"error" => "JSON provided is invalid. See http://json.org/ to see how to format correctly."})
        rescue IOError => e
          self.close!
        end
      end
    end
  end
  
  # I think you can guess this one
  def connected?
    self.class.connections.include? self
  end
  
  # closes the connection and the threads and stuff for this user
  def close!
    return if @disconnected == true
    
    @disconnected = true
    puts "User #{self.inspect} disconnecting" if self.class.log?
    
    # notify the remote side
    notify!('**remote__disconnecting**') rescue nil
    
    if @parent
      @parent.event(:disconnect, self)
      @parent.incoming_mutex.synchronize { @parent.incoming.delete(self) }
    else
      self.class.outgoing_mutex.synchronize { self.class.outgoing.delete(self) }
    end
    
    Thread.new { sleep(1); @socket.close rescue nil }
  end
  
  # send a notification to this user
  def notify!(method, *args)
    puts "Notify #{self.__inspect}: #{method}(#{args.map { |i| i.inspect }.join(', ')})" if self.__class.log?
    self.__send_data!({'method' => method.to_s, 'params' => args, 'id' => nil})
  end
  
  # sends a normal RPC request that has a response
  def send!(method, *args)
    puts "Call #{self.__inspect}: #{method}(#{args.map { |i| i.inspect }.join(', ')})" if self.__class.log?
    id = self.__get_unique_number
    self.send_data! 'method' => method.to_s, 'params' => args, 'id' => id
    
    while @responses_mutex.synchronize { @responses.keys.include?(id) } == false
      sleep(0.01)
    end
    
    data = @responses_mutex.synchronize { @responses.delete(id) }
    
    error = data['error']
    raise error unless error.nil?
    
    puts ">> #{method} #=> #{data['result'].inspect}" if self.__class.log?
    
    return data['result']
  end
  
  def inspect
    "<Legs:#{__object_id} Meta: #{@meta.inspect}>"
  end
  
  # does an async request which calls a block when response arrives
  def send_async!(method, *args, &blk)
    puts "Call #{self.__inspect}: #{method}(#{args.map { |i| i.inspect }.join(', ')})" if self.__class.log?
    id = self.__get_unique_number
    self.send_data! 'method' => method.to_s, 'params' => args, 'id' => id
    
    Thread.new do
      while @responses_mutex.synchronize { @responses.keys.include?(id) } == false
        sleep(0.05)
      end
      
      data = @responses_mutex.synchronize { @responses.delete(id) }
      puts ">> #{method} #=> #{data['result'].inspect}" if self.__class.log? unless data['error']
      blk[Legs::AsyncData.new(data)]
    end
  end
  
  # maps undefined methods in to rpc calls
  def method_missing(method, *args)
    return self.send(method, *args) if method.to_s =~ /^__/
    send!(method, *args)
  end
  
  # hacks the send method so ancestor methods instead become rpc calls too
  # if you want to use a method in a Legs superclass, prefix with __
  def send(method, *args)
    return super(method.to_s.sub(/^__/, ''), *args) if method.to_s =~ /^__/
    return super(method, *args) if self.__public_methods(false).include?(method)
    super('send!', method.to_s, *args)
  end

  # sends raw object over the socket
  def send_data!(data)
    raise "Lost remote connection" unless connected?
    @socket_mutex.synchronize { @socket.write(JSON.generate(__json_marshal(data)) + self.__class.terminator) }
  end
  
  
  private
  
  # takes a ruby object, and converts it if needed in to marshalled hashes
  def json_marshal(object)
    case object
    when Bignum, Fixnum, Integer, Float, TrueClass, FalseClass, String, NilClass
      return object
    when Hash
      out = Hash.new
      object.each_pair { |k,v| out[k.to_s] = __json_marshal(v) }
      return out
    when Array
      return object.map { |v| __json_marshal(v) }
    else
      return {'__jsonclass__' => [object.class.name, object._dump]} if object.respond_to?(:_dump)
      
      # the default marshalling behaviour
      instance_vars = {}
      object.instance_variables.each do |var_name|
        instance_vars[var_name.to_s.sub(/@/, '')] = self.__json_marshal(object.instance_variable_get(var_name))
      end
      
      return {'__jsonclass__' => [object.class.name]}.merge(instance_vars)
    end
  end
  
  # takes an object from the network, and decodes any marshalled hashes back in to ruby objects
  def json_restore(object)
    case object
    when Hash
      if object.keys.include? '__jsonclass__'
        constructor = object.delete('__jsonclass__')
        class_name = constructor.shift.to_s
        object_class = Module.const_get(class_name) rescue false
        
        if object_class.name == class_name
          return object_class._load(*constructor) if object_class.respond_to?(:_load) unless constructor.empty?
          
          instance = object_class.allocate
          object.each_pair do |key, value|
            instance.instance_variable_set("@#{key}", self.__json_restore(value))
          end
          return instance
        else
          raise "Response contains a #{class_name} but that class is not loaded locally."
        end
      else
        hash = Hash.new
        object.each_pair { |k,v| hash[k] = self.__json_restore(v) }
        return hash
      end
    when Array
      return object.map { |i| self.__json_restore(i) }
    else
      return object
    end
  end
  
  # gets a unique number that we can use to match requests to responses
  def get_unique_number; @unique_id ||= 0; @unique_id += 1; end
end


# the server is started by subclassing Legs, then SubclassName.start
class << Legs
  attr_accessor :terminator, :log
  attr_reader :incoming, :outgoing, :server_object, :incoming_mutex, :outgoing_mutex, :messages_mutex
  alias_method :log?, :log
  alias_method :users, :incoming
  
  def initializer
    ObjectSpace.define_finalizer(self) { self.stop! }
    @incoming = []; @outgoing = []; @messages = Queue.new; @terminator = "\n"; @log = true
    @incoming_mutex = Mutex.new; @outgoing_mutex = Mutex.new
  end
  
  
  # starts the server, pass nil for port to make a 'server' that doesn't actually accept connections
  # This is useful for adding methods to Legs so that systems you connect to can call methods back on you
  def start(port=30274, &blk)
    return if started?
    raise "Legs.start requires a block" unless blk
    @started = true
    
    # make the fake class
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
        server.incoming.find { |user| user.__object_id == value }
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
    @server_class.module_eval(&blk)
    @server_object = @server_class.allocate
    @server_object.instance_variable_set(:@server, self)
    @server_object.instance_eval { initialize }
    
    @message_processor = Thread.new do
      while started?
        sleep(0.01) and next if @messages.empty?
        data, from = @messages.deq
        method = data['method']; params = data['params']
        methods = @server_object.public_methods(false)
        
        # close dead connections
        from.close! and next if data['method'] == '**remote__disconnecting**'
        
        begin
          raise "Supplied method is not a String" unless method.is_a?(String)
          raise "Supplied params object is not an Array" unless params.is_a?(Array)
          raise "Cannot run '#{method}' because it is not defined in this server" unless methods.include?(method.to_s) or methods.include? :method_missing
          
          puts "Call #{method}(#{params.map { |i| i.inspect }.join(', ')})" if log?
          
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
          puts "Backtrace: \n" + e.backtrace.map { |i| "   #{i}" }.join("\n") if log?
        end
      end
    end
    
    unless port.nil? or port == false
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
  
  # returns true if server is running
  def started?; @started; end
  
  # creates a legs client, and passes it to supplied block, closes client after block finishes running
  # I wouldn't have added this method to keep shoes small, but users insist comedic value makes it worthwhile
  def open(*args, &blk)
    client = Legs.new(*args)
    blk[client]
    client.close!
  end
  
  # hooks up these methods so you can use them off the main object too!
  [:broadcast, :find_user_by_object_id, :find_users_by_meta].each do |name|
    define_method name do |*args|
      @incoming_mutex.synchronize do
        @server_object.__send__(name, *args)
      end
    end
  end
end

Legs.initializer


class Legs::AsyncData
  def initialize(data); @data = data; end
  def result
    @errored = true and raise @data['error'] if @data['error'] unless @errored
    return @data['result']
  end
  alias_method :value, :result
end

class Legs::StartBlockError < StandardError; end
class Legs::RequestError < StandardError; end
