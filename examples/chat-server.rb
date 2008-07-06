require '../legs'

# this is a work in progress, api's will change and break, one day there will be a functional matching
# client in shoes or something

Legs.start do
  @rooms = {}
  # returns a list of available rooms
  def available_rooms; @rooms.keys; end
  
  # joins/creates a room
  def join(room_name)
    room = @rooms[room_name.to_s] ||= {'users' => [], 'messages' => [], 'topic' => 'No topic set'}
    broadcast_to room, 'user_joined', user_object(self.caller)
    room['users'].push(self.caller) unless room['users'].include?(self.caller)
    return_obj = room.dup
    return_obj['users'].map! { |user| user_object(user) }
    return_obj
  end
  
  # leaves a room
  def leave(room_name)
    room = @rooms[room.to_s]
    room['users'].delete(self.caller)
    broadcast_to room, 'user_left', room_name, user_object(self.caller)
    @rooms.delete(room_name.to_s) if room['users'].empty?
  end
  
  # sets the room topic message
  def set_topic(room, message)
    @rooms[room.to_s]['topic'] = message.to_s
    broadcast_to room, 'room_changed', {'room' => room.to_s, 'topic' => message.to_s}
  end
  
  # sets the user's name
  def set_name(name)
    self.caller.meta[:name] = name.to_s
    user_rooms(self.caller).each do |room_name|
      broadcast_to room_name, 'user_changed', user_object(self.caller)
    end
  end
  
  # returns information about ones self, clients thusly can find out their user 'id' number
  def user_info(object_id = nil)
    user = object_id.nil? ? self.caller : users.select { |u| u.object_id == object_id.to_i }.first
    user_object(user)
  end
  
  # posts a message to a room
  def post_message(room_name, message)
    room = @rooms[room_name.to_s]
    room.messages.push(msg = ['user' => user_object(self.caller), 'time' => Time.now.to_i, 'message' => message.to_s} )
    trim_messages(room_name.to_s)
    broadcast_to room, 'room_message', room_name.to_s, user_object(object_id), message.to_s
  end
  
  private
  
  # trims the message backlog
  def trim_messages room
    while room['messages'].length > 250
      room['messages'].shift
    end
  end
  
  # sends a notification to members of a room
  def broadcast_to room, *args
    room = @rooms[room.to_s] if room.is_a? String
    room['users'].each do |user|
      user.notify! *args
    end
    return true
  end
  
  # makes a user object suitable for sending back with meta info and stuff
  def user_object user
    object = {'id' => user.object_id}
    user.meta.each_pair do |key, value|
      object[key.to_s] = value
    end
    return object
  end
  
  # returns all the room names the user is in.
  def user_rooms user
    @rooms.values.select { |room| room['users'].include?(user) }.map { |room| @rooms.index(room) }
  end
end


ChatServer.start
sleep