# Legs take you places, a networking companion to Shoes
require 'rubygems'
require 'json' unless self.class.const_defined? 'JSON'
require 'socket'
require 'thread'

Thread.abort_on_exception = true

class Legs
  attr_reader :socket, :parent, :meta
  
  # Legs.new for a client, subclass to make a server, .new then makes server and client!
  def initialize(host = 'localhost', port = 30274)
    self.class.start(port) if self.class != Legs && !self.class.started?
    ObjectSpace.define_finalizer(self) { self.close! }
    @socket = TCPSocket.new(host, port) if host.instance_of?(String)
    @socket = host and @parent = port if host.instance_of?(TCPSocket)
    @responses = {}; @meta = {}; @parent ||= self.class
    
    @handle_data = Proc.new do |data|
      print ": #{data}" if self.class.log?
      
      data = self.__json_restore(JSON.parse(data))
      
      if @parent and data['method']
        @parent.__data!(data, self)
      elsif data['error'] and data['id'].nil?
        raise Exception(data['error']).new
      else
        @responses[data['id']] = data
      end
    end
    
    @thread = Thread.new do
      while connected?
        begin
          self.close! if @socket.eof?
          @handle_data[@socket.gets(self.class.terminator)]
        rescue JSON::ParserError => e
          self.__send_data!({"error" => "JSON provided is invalid. See http://json.org/ to see how to format correctly."})
        rescue IOError => e
          self.close!
        end
      end
    end
    
    @async_space_class = Class.new
    @async_space_class.module_eval do
      def result
        @errored = true and raise Exception.new(@data['error'].to_s) if @data['error'] unless @errored
        return @data['result']
      end
      
      def method_missing(meth, *args); end
    end
  end
  
  # I think you can guess this one
  def connected?; !@socket.closed?; end
  
  # closes the connection and the threads and stuff for this user
  def close!
    return unless connected?
    puts "User #{self.inspect} disconnecting" if self.class.log?
    @parent.__on_disconnect(self) if @parent and @parent.respond_to? :__on_disconnect
    @socket.close 
    @parent.users.delete(self) if @parent
  end
  
  # send a notification to this user
  def notify!(method, *args)
    self.__send_data!({'method' => method.to_s, 'params' => args, 'id' => nil})
  end
  
  # sends a normal RPC request that has a response
  def send!(method, *args)
    id = self.__get_unique_number
    self.__send_data! 'method' => method.to_s, 'params' => args, 'id' => id
    
    while @responses.keys.include?(id) == false
      sleep(0.05)
    end
    
    data = @responses.delete(id)
    
    error = data['error']
    error = Exception.new(error) if error.instance_of?(String)
    raise error unless error.nil?
    return data['result']
  end
  
  # does an async request which calls a block when response arrives
  def send_async!(method, *args, &blk)
    id = self.__get_unique_number
    self.send_data! 'method' => method.to_s, 'params' => args, 'id' => id
    
    Thread.new do
      while @responses.keys.include?(id) == false
        sleep(0.05)
      end
      
      async_space = @async_space_class.allocate
      async_space.instance_variable_set(:@data, @responses.delete(id))
      async_space.instance_variable_set(:@binding, blk.binding)
      async_space.instance_eval blk
    end
  end
  
  def method_missing(method, *args)
    return self.send(method, *args) if method.to_s =~ /^__/
    super(method, *args)
  end
  
  # hacks the send method so ancestor methods don't get in the way, if you want to use one, prefix with __
  def send(method, *args)
    return super(method.to_s.sub(/^__/, ''), *args) if method.to_s =~ /^__/
    return super(method, *args) if self.__public_methods(false).include?(method)
    super('send!', method.to_s, *args)
  end

  # sends raw object over the socket
  def send_data!(data)
    message = JSON.generate(__json_marshall(data)) + self.__class.terminator
    @socket.write(message)
    puts "> #{message}" if self.class.log?
  end
  
  
  private
  
  # takes a ruby object, and converts it if needed in to marshalled hashes
  def json_marshall(object)
    safelist = [Array, Hash, Bignum, Fixnum, Integer, Float, TrueClass, FalseClass, String]
    return object if object.class.ancestors.detect(false) { |i| safelist.include?(i) }
    
    return {'__jsonclass__' => [object.class.name, object._dump]} if object.respond_to?(:_dump)
    
    # the default marshalling behaviour
    instance_vars = {}
    object.instance_variables.each do |var_name|
      instance_vars[varname.to_s.sub(/@/, '')] = self.__json_marshall(object.instance_variable_get(varname))
    end
    
    return {'__jsonclass__' => [object.class.name]}.merge(instance_vars)
  end
  
  # takes an object from the network, and decodes any marshalled hashes back in to ruby objects
  def json_restore(object)
    if object.is_a?(Hash) and object['__jsonclass__']
      object_class = Module.const_get(object_name = object['__jsonclass__'].shift.to_s) rescue false
      if object_class
        constructor = object.delete('__jsonclass__')
        
        return object_class._load(*constructor) if object_class.respond_to?(:_load) unless constructor.empty?
        
        instance = object_class.allocate
        object.each_pair do |key, value|
          instance.instance_variable_set("@#{key}", self.__json_restore(value))
        end
        return instance
      else
        raise Exception.new("Response contains a #{object_name} but that class is not loaded locally.")
      end
    else
      return object
    end
  end
  
  # gets a unique number that we can use to match requests to responses
  def get_unique_number; @unique_id ||= 0; @unique_id += 1; end
end


# the server is started by subclassing Legs, then SubclassName.start
class << Legs
  attr_writer :terminator
  attr_reader :caller
  def terminator; @terminator || "\n"; end
  def users; @users || []; end
  attr_writer :log
  def log?; @log || true; end
  
  # starts the server, pass nil for port to make a 'server' that doesn't actually accept connections
  # This is useful for adding methods to Legs so that systems you connect to can call methods back on you
  def start(port=30274, &blk)
    return if started?
    raise "Legs.start requires a block" unless blk
    ObjectSpace.define_finalizer(self) { self.stop! }
    @users = []; @messages = []; @started = true
    
    unless port.nil? or port == false
      @listener = TCPServer.new(port)
      
      @acceptor_thread = Thread.new do
        while started?
          @users.push(user = Legs.new(@listener.accept, self))
          puts "User #{user.object_id} connected, now there are #{@users.length} users" if log?
          __on_connect(user) if respond_to? :__on_connect
        end
      end
    end
    
    @message_processor = Thread.new do
      while started?
        sleep(0.05) and next if @messages.empty?
        data, from = @messages.shift
        method = data['method']; params = data['params']
        begin
          puts "Method: #{method}"
          if @server_object.public_methods(false).include?(method.to_s)
            params = [] unless params.is_a?(Array)
            @server_object.instance_variable_set(:@caller, from)
            result = @server_object.__send__(method.to_s, *params)
            from.__send_data!({'id' => data['id'], 'result' => result}) unless data['id'].nil?
          else
            raise Exception.new("Cannot run '#{data['method']}' because it is not defined in this server")
          end
        rescue Exception => e
          from.__send_data!({'error' => e.to_s, 'id' => data['id']}) unless data['id'].nil?
        end
      end
    end
    
    # make the fake class
    @server_class = Class.new
    @server_class.module_eval { private; attr_reader :server, :caller; public }
    @server_class.module_eval(&blk)
    @server_object = @server_class.allocate
    @server_object.instance_variable_set(:@server, self)
    @server_object.initialize if @server_object.respond_to?(:initialize)
    
  end
  
  # stops the server, disconnects the clients
  def stop!
    @started = false
    @users.each { |user| user.close! }
  end
  
  # sends a notification message to all connected clients
  def broadcast!(method, *args)
    @users.each { |user| user.notify!(method, *args) }
  end
  
  # gets called to handle all incomming messages (RPC requests)
  def __data!(data, from)
    @messages.push([data, from])
  end
  
  # returns true if server is running
  def started?; @started; end
end
