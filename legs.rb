# Legs take you places, a networking companion to Shoes
require 'rubygems'
require 'json' unless self.class.const_defined? 'JSON'
require 'socket'
require 'thread'

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
          self.__send_data({"error" => "JSON provided is invalid"})
        rescue IOError => e
          self.close!
        end
      end
    end
  end
  
  # I think you can guess this one
  def connected?; !@socket.closed?; end
  
  # closes the connection and the threads and stuff for this user
  def close!
    return unless connected?
    puts "User #{self.object_id} disconnecting" if self.class.log?
    @parent.__on_disconnect(self) if @parent and @parent.respond_to? :__on_disconnect
    @socket.close 
    @parent.users.delete(self) if @parent
  end
  
  # send a notification to this user
  def notify!(method, *args)
    self.__send_data({'method' => method.to_str, 'params' => self.__json_marshall(args)})
  end
  
  # sends a normal RPC request that has a response
  def send!(method, *args)
    id = self.__get_unique_number
    data = {'id' => id, 'method' => method.to_s, 'params' => self.__json_marshall(args)}
    self.__send_data data
    
    while @responses.keys.include?(id) == false
      sleep(0.05)
    end
    
    data = @responses.delete(id)
    
    error = data['error']
    error = Exception.new(error) if error.instance_of?(String)
    raise error unless error.nil?
    return data['result']
  end
  
  # makes it so for stuff that isn't built in to module or class or object instance methods, we can call with legs.thing
  def method_missing(name, *args)
    self.send!(name, *args)
  end
  
  # takes a ruby object, and converts it if needed in to marshalled hashes
  def __json_marshall(object)
    safelist = [Array, Hash, Bignum, Fixnum, Integer, Float, TrueClass, FalseClass, String]
    return object if object.class.ancestors.detect(false) { |i| safelist.include?(i) }
    
    return {'__jsonclass__' => [object.class.name, object._dump]} if object.respond_to?(:_dump)
    
    # the default marshalling behaviour
    instance_vars = {}
    object.instance_variables.each do |var_name|
      instance_vars[varname.to_s.gsub(/@/, '')] = self.__json_marshall(object.instance_variable_get(varname))
    end
    
    return {'__jsonclass__' => [object.class.name]}.merge(instance_vars)
  end
  
  # takes an object from the network, and decodes any marshalled hashes back in to ruby objects
  def __json_restore(object)
    if object.is_a?(Hash) && object['__jsonclass__']
      if const_defined?(object['__jsonclass__'])
        constructor = object.delete('__jsonclass__')
        object_class = const_get(constructor.shift)
        
        return object_class._load(*constructor) if object_class.respond_to?(:_load) unless constructor.empty?
        
        
        instance = object_class.allocate
        object.each_pair do |key, value|
          instance.instance_variable_set("@#{key}", self.__json_restore(value))
        end
        return instance
      else
        raise Exception.new("Response contains a #{object['__jsonclass__']} but that class is not loaded locally.")
      end
    else
      return object
    end
  end
  
  # sends raw object over the socket
  def __send_data(data)
    message = JSON.generate(data) + self.class.terminator
    @socket.write(message)
    puts "> #{message}" if self.class.log?
  end
  
  # gets a unique number that we can use to match requests to responses
  def __get_unique_number; @unique_id ||= 0; @unique_id += 1; end
end


# the server is started by subclassing Legs, then SubclassName.start
class << Legs
  attr_writer :terminator
  attr_reader :caller
  def terminator; @terminator || "\n"; end
  def users; @users || []; end
  attr_writer :log
  def log?; @log || true; end
  
  # starts the server
  def start(port=30274)
    return if started?
    raise "You need to subclass Legs!" if self == Legs
    ObjectSpace.define_finalizer(self) { self.stop! }
    
    @listener = TCPServer.new(port)
    @users = []; @messages = []; @started = true
    
    @acceptor_thread = Thread.new do
      while started?
        @users.push(user = Legs.new(@listener.accept, self))
        puts "User #{user.object_id} connected, now there are #{@users.length} users" if log?
        __on_connect(user) if respond_to? :__on_connect
      end
    end
    
    @message_processor = Thread.new do
      while started?
        sleep(0.05) and next if @messages.empty?
        data, from = @messages.shift
        begin
          if self.class.public_method_defined?(data['method']) # self.class.instance_methods(false).include?(data['method']) && 
            data['params'] = [] unless data['params'].is_a?(Array)
            @caller = from
            result = self.__send__(data['method'], *data['params'])
            from.__send_data({'id' => data['id'], 'result' => result}) unless data['id'].nil?
          else
            raise Exception.new("Cannot run #{data['method']}() because it is not defined in this server")
          end
        rescue Exception => e
          from.__send_data({'error' => e.to_s, 'id' => data['id']}) unless data['id'].nil?
        end
      end
    end
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