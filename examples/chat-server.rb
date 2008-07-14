require '../lib/legs'

# this is a work in progress, api's will change and break, one day there will be a functional matching
# client in shoes or something

Legs.start do
  def initialize
    @rooms = Hash.new { {'users' => [], 'messages' => [], 'topic' => 'No topic set'} }
    @rooms['Lobby'] = {'topic' => 'General Chit Chat', 'messages' => [], 'users' => []}
  end
  
  # returns a list of available rooms
  def rooms
    room_list = Hash.new
    @rooms.keys.each { |rn| room_list[rn] = room_object rn, :remote, :topic, :users, :messages }
    room_list
  end
  
  # joins/creates a room
  def join(room_name)
    unless @rooms.keys.include?(room_name)
      @rooms[room_name.to_s] = @rooms[room_name]
      broadcast :room_created, room_name
    end
    
#     room = room_object(room_name)
#     
#     unless room['users'].include?(caller)
#       broadcast room['users'], 'user_joined', room_name, user_object(caller)
#       room['users'].push(caller)
#     end
    
    room_object room_name, :remote
  end
  
  # leaves a room
  def leave(room_name)
    room = @rooms[room_name.to_s]
    room['users'].delete(caller)
    broadcast room['users'], 'user_left', room_name, user_object(caller)
    true
  end
  
  # sets the room topic message
  def topic=(room, message)
    room = @rooms[room.to_s]
    room['topic'] = message.to_s
    broadcast room['users'], 'room_changed', room_object(room, :remote, :name, :topic)
  end
  
  # sets the user's name
  def name=(name)
    caller.meta[:name] = name.to_s
    user_rooms(caller).each do |room_name|
      broadcast @rooms[room_name]['users'], 'user_changed', user_object(caller)
    end
    true
  end
  
  # returns information about ones self, clients thusly can find out their user 'id' number
  def user(object_id = nil)
    user = user_object( object_id.nil? ? caller : find_user_by_object_id(object_id) }.first )
    user['rooms'] = user_rooms(user)
    return user
  end
  
  # posts a message to a room
  def post_message(room_name, message)
    room = room_object(room_name)
    room['messages'].push(msg = {'user' => user_object(caller), 'time' => Time.now.to_i, 'message' => message.to_s} )
    trim_messages room
    broadcast room['users'], 'message', room_name.to_s, msg
    return msg
  end
  
  private
  
  # trims the message backlog
  def trim_messages room
    room = room_object(room) if room.is_a?(String)
    while room['messages'].length > 250
      room['messages'].shift
    end
  end
  
  # makes a user object suitable for sending back with meta info and stuff
  def user_object user
    object = {'id' => user.object_id}
    user.meta.each_pair do |key, value|
      object[key.to_s] = value
    end
    return object
  end
  
  def room_object room_name, target = :local, *only
    object = @rooms[room_name.to_s].dup
    object['users'].delete_if {|user| user.connected? == false }
    object['users'] = object['users'].map { |user| user_object(user) } if target == :remote
    object['topic'] = 'No topic set' if object['topic'].nil? or object['topic'].empty?
    object['name'] = room_name.to_s if target == :remote
    object.delete_if { |key, value| only.include?(key.to_sym) == false } unless only.empty?
    object
  end
  
  # returns all the room names the user is in.
  def user_rooms user
    @rooms.values.select { |room| room['users'].include?(user) }.map { |room| @rooms.index(room) }
  end
end

sleep